import Vision
import PDFKit
import AppKit

// MARK: - Scan result type

/// Carries the decoded barcode, checkbox classification, the crop image of the
/// checkbox row for visual confirmation, and PNG-encoded crops of the two
/// handwritten sections for direct storage in CoreData.
struct ScanResult {
    /// The confirmed Code-128 barcode string (individual paper barcode).
    let barcodeValue: String
    /// When the PDF starts with a batch label page, this carries the batch barcode.
    /// nil for non-batch PDFs.
    let batchBarcodeValue: String?
    /// Cropped CGImage of the Completed row for visual confirmation.
    /// `nil` when the barcode was entered manually (no PDF available).
    let checkboxRegionImage: CGImage?
    /// Optical inference from half-density pixel analysis.
    /// "practice" | "timed" | nil (no mark detected or no PDF).
    let inferredPaperType: String?
    /// PNG-encoded crop of the คำถามที่ต้องดู section.  Saved directly to
    /// `AttemptMO.difficultQuestionsImageData` on check-in.
    let difficultQuestionsImageData: Data?
    /// PNG-encoded crop of the Additional Notes section.  Saved directly to
    /// `AttemptMO.additionalNotesImageData` on check-in.
    let additionalNotesImageData: Data?

    /// Convenience init (all callers, including manual-entry, use this).
    /// Marked `nonisolated` so it can be called from non-`@MainActor` contexts
    /// such as the `VisionBarcodeScanner` actor without a concurrency warning.
    nonisolated init(barcodeValue: String,
                     batchBarcodeValue: String? = nil,
                     checkboxRegionImage: CGImage?,
                     inferredPaperType: String?,
                     difficultQuestionsImageData: Data? = nil,
                     additionalNotesImageData: Data? = nil) {
        self.barcodeValue                = barcodeValue
        self.batchBarcodeValue           = batchBarcodeValue
        self.checkboxRegionImage         = checkboxRegionImage
        self.inferredPaperType           = inferredPaperType
        self.difficultQuestionsImageData = difficultQuestionsImageData
        self.additionalNotesImageData    = additionalNotesImageData
    }
}

// MARK: - VECTROX region descriptor

/// Pixel-precise bounding rectangles derived from VECTROX horizontal rule
/// detection.  All rects are in CG image pixel space (y = 0 at TOP), sized
/// for the 2× render scale used throughout the scanner pipeline.
private struct VectroxRegions {
    /// Full-width crop of the Completed row (top border → internal lighter rule).
    let checkboxRect: CGRect
    /// Full-width crop spanning the คำถามที่ต้องดู label + content box.
    let reviewRect:   CGRect
    /// Full-width crop spanning the Additional Notes label + content box.
    let notesRect:    CGRect
}

// MARK: - Scanner actor

/// Multi-pass Code-128 barcode scanner with VECTROX anchor-based region
/// clipping and deterministic 180° orientation correction.
///
/// ## Orientation detection (VECTROX barcode-envelope anchor)
///
/// The printed Code-128 barcode lives in the page header — the uppermost
/// region of an upright sheet.  In Vision coordinates (y = 0 at BOTTOM), an
/// upright barcode has `midY > 0.50`.  If `midY < 0.45` the page is inverted
/// and a 180° affine rotation is applied before any further processing.
///
/// Priority ladder inside `renderAutoOriented`:
///   1. `PDFPage.rotation == 180` metadata → immediate flip.
///   2. Barcode-envelope midY probe (Vision space) → primary orientation check.
///   3. Last-resort 180° flip (caught by belt-and-suspenders re-probe in callers).
///
/// ## VECTROX horizontal rule scanner
///
/// `vectroxScanHorizontalRules(_:)` renders the oriented page to an 8-bit
/// grayscale pixel buffer and scans every row.  Any row where ≥ 65 % of the
/// inner 90 % of pixels are darker than brightness 80/255 is classified as a
/// printed rule line.  Consecutive dark rows are merged into a single band;
/// the centroid row index is recorded.
///
/// `vectroxDetectRegions(_:)` then builds a gap list between consecutive rules,
/// filters to gaps that are:
///   • at least 2.8 % of page height (≈ 47 px at A4 2×, eliminating 12-pt
///     info-table header rows at ≈ 24 px while retaining the 32-pt checkbox
///     strip at ≈ 64 px), and
///   • below 20 % from the top (excluding the header band and info table).
///
/// For the standard A4 template the result is exactly three gaps in order:
///
///   | Region          | CG px (top → bot) | Height  |
///   |-----------------|-------------------|---------|
///   | Checkbox strip  | ~368 → ~434       | ~66 px  |
///   | Review content  | ~472 → ~914       | ~442 px |
///   | Notes content   | ~952 → ~1636      | ~684 px |
///
/// The three crop rectangles are derived as:
///   • `checkboxRect` = raw checkbox gap (left 65 % wide)
///   • `reviewRect`   = checkbox_bottom → review_content_bottom (includes label)
///   • `notesRect`    = review_content_bottom → notes_content_bottom (includes label)
///
/// Falls back to calibrated percentage constants when fewer than three
/// qualifying gaps are detected.
///
/// ## Fallback constants (when VECTROX yields < 3 gaps)
///
///   | Region    | Y top | Y bot |
///   |-----------|-------|-------|
///   | Checkbox  | 0.42  | 0.50  |
///   | Review    | 0.42  | 0.70  |
///   | Notes     | 0.70  | 0.95  |
actor VisionBarcodeScanner {

    // MARK: - Error surface

    enum ScanError: LocalizedError {
        case pdfUnreadable
        case pageRenderFailed
        case inconsistentReads(attempts: [String])
        case noBarcodesFound

        var errorDescription: String? {
            switch self {
            case .pdfUnreadable:        return "Could not open the PDF file."
            case .pageRenderFailed:     return "Failed to render the first page for scanning."
            case .noBarcodesFound:      return "No barcode detected on the first page."
            case .inconsistentReads(let a):
                return "Barcode reads were inconsistent across 3 passes: \(a.joined(separator: ", "))"
            }
        }
    }

    // MARK: - Fallback constants (CG space, y = 0 at TOP)
    //
    // Used when VECTROX detects fewer than 3 qualifying gaps.
    //
    // Checkbox Row Strip:
    //   X = 0,  Y = H × 0.42,  W = W × 1.00 (full width — shows "Completed:" label + both checkboxes)
    //   Crop midX = 0.325 → cb1 (Practice, ~0.175) left ✓, cb2 (Timed, ~0.360) right ✓
    //
    // คำถามที่ต้องดู (Difficult Questions):  Y 0.42 → 0.70  (includes label + content)
    // Additional Notes:                      Y 0.70 → 0.95  (includes label + content)

    private static let regionXNorm: CGFloat = 0.00
    // Checkbox row: shifted ~5 pt UPWARD (checkboxes straddle the rule boundary).
    // 0.42 → 0.414 (≈ 10 px higher at 2× = 5 pt upward).
    private static let regionYNorm: CGFloat = 0.414
    private static let regionWNorm: CGFloat = 1.00   // full page width — shows "Completed:" label + both checkboxes + labels
    private static let regionHNorm: CGFloat = 0.062  // ≈102 px at A4 2× — tight around the Completed row only

    // Review section: top shifted up by ~30 pt (30/841.89 ≈ 0.036) so the
    // "คำถามที่ต้องดู" title label is never clipped.
    // Original top 0.42 → 0.384 (rounds to 0.384).
    private static let reviewTopNorm:    CGFloat = 0.384
    private static let reviewBottomNorm: CGFloat = 0.70
    private static let notesTopNorm:     CGFloat = 0.70
    private static let notesBottomNorm:  CGFloat = 0.95
    private static let sectionXNorm:     CGFloat = 0.00
    private static let sectionWNorm:     CGFloat = 1.00

    private static let markDensityFloor: Double = 0.005   // 0.5 % dark-pixel threshold

    // MARK: - Public: barcode-only scan

    func scan(pdfURL: URL) async throws -> String {
        guard let doc = PDFDocument(url: pdfURL) else { throw ScanError.pdfUnreadable }
        guard let page = doc.page(at: 0)          else { throw ScanError.pdfUnreadable }
        let img = try renderAutoOriented(page: page, scale: 2.0)
        return try extractBarcode(from: img)
    }

    // MARK: - Public: barcode + checkbox + section scan

    /// Decodes the barcode, classifies the paper type, and returns a `ScanResult`
    /// containing:
    ///   - `checkboxRegionImage`: CGImage crop of the Completed row (for
    ///     `ValidationPaneView` visual confirmation).
    ///   - `difficultQuestionsImageData`: PNG of the คำถามที่ต้องดู section.
    ///   - `additionalNotesImageData`: PNG of the Additional Notes section.
    ///
    /// **Region derivation** uses the VECTROX horizontal-rule scanner to locate
    /// table boundaries directly from the rendered pixel data.  Falls back to
    /// calibrated percentage constants when VECTROX detects fewer than three
    /// qualifying gaps.
    ///
    /// **Orientation guarantee**: all crops are extracted from an upright image.
    /// A belt-and-suspenders barcode-midY re-probe after `renderAutoOriented`
    /// corrects any wrong-direction flip from the last-resort step.
    func scanWithCheckbox(pdfURL: URL) async throws -> ScanResult {
        guard let doc = PDFDocument(url: pdfURL) else { throw ScanError.pdfUnreadable }
        guard let page0 = doc.page(at: 0)        else { throw ScanError.pdfUnreadable }

        var page0Image = try renderAutoOriented(page: page0, scale: 2.0)
        if let obs = try? detectBarcodeObservation(in: page0Image),
           obs.boundingBox.midY < 0.45 {
            page0Image = flipVertical(page0Image) ?? page0Image
        }

        let page0Barcode = try extractBarcode(from: page0Image)

        // ── Batch PDF detection ───────────────────────────────────────────────
        // Structure (label removed):
        //   Page 0: Batch Examination Records Index List  → BATCH-* barcode
        //   Page 1: Individual paper Examination Records Index  ← scan this
        //   Pages 2+: Past paper content
        if page0Barcode.hasPrefix("BATCH-") {
            let batchBarcode = page0Barcode

            // Scan page 1 (index 1) for the individual paper barcode + sections
            guard let indexPage = doc.page(at: 1) else {
                throw ScanError.noBarcodesFound
            }
            var indexImage = try renderAutoOriented(page: indexPage, scale: 2.0)
            if let obs = try? detectBarcodeObservation(in: indexImage),
               obs.boundingBox.midY < 0.45 {
                indexImage = flipVertical(indexImage) ?? indexImage
            }
            let paperBarcode = try extractBarcode(from: indexImage)

            let vectrox = vectroxDetectRegions(in: indexImage)
            let regionRect  = vectrox?.checkboxRect ?? checkboxRegionRect(for: indexImage)
            let inferredType = inferTypeByHalfDensity(in: indexImage, regionRect: regionRect)
            let regionImage  = cropCGImage(from: indexImage, rect: regionRect)

            let reviewCrop: CGImage?
            let notesCrop:  CGImage?
            if let v = vectrox {
                reviewCrop = cropCGImage(from: indexImage, rect: v.reviewRect)
                notesCrop  = cropCGImage(from: indexImage, rect: v.notesRect)
            } else {
                reviewCrop = cropSection(from: indexImage, topNorm: Self.reviewTopNorm,    bottomNorm: Self.reviewBottomNorm)
                notesCrop  = cropSection(from: indexImage, topNorm: Self.notesTopNorm,     bottomNorm: Self.notesBottomNorm)
            }

            return ScanResult(
                barcodeValue:                paperBarcode,
                batchBarcodeValue:           batchBarcode,
                checkboxRegionImage:         regionImage,
                inferredPaperType:           inferredType,
                difficultQuestionsImageData: reviewCrop.flatMap { cgImageToPNGData($0) },
                additionalNotesImageData:    notesCrop.flatMap  { cgImageToPNGData($0) }
            )
        }

        // ── Standard (non-batch) PDF ──────────────────────────────────────────
        let barcodeValue = page0Barcode
        let cgImage      = page0Image

        let vectrox = vectroxDetectRegions(in: cgImage)
        let regionRect = vectrox?.checkboxRect ?? checkboxRegionRect(for: cgImage)

        let inferredType = inferTypeByHalfDensity(in: cgImage, regionRect: regionRect)
        let regionImage  = cropCGImage(from: cgImage, rect: regionRect)

        let reviewCrop: CGImage?
        let notesCrop:  CGImage?
        if let v = vectrox {
            reviewCrop = cropCGImage(from: cgImage, rect: v.reviewRect)
            notesCrop  = cropCGImage(from: cgImage, rect: v.notesRect)
        } else {
            reviewCrop = cropSection(from: cgImage,
                                     topNorm: Self.reviewTopNorm,
                                     bottomNorm: Self.reviewBottomNorm)
            notesCrop  = cropSection(from: cgImage,
                                     topNorm: Self.notesTopNorm,
                                     bottomNorm: Self.notesBottomNorm)
        }

        return ScanResult(
            barcodeValue:                barcodeValue,
            batchBarcodeValue:           nil,
            checkboxRegionImage:         regionImage,
            inferredPaperType:           inferredType,
            difficultQuestionsImageData: reviewCrop.flatMap { cgImageToPNGData($0) },
            additionalNotesImageData:    notesCrop.flatMap  { cgImageToPNGData($0) }
        )
    }

    // MARK: - Public: standalone section image extraction

    /// Renders the first page of `pdfURL`, applies orientation correction, and
    /// returns `CGImage` crops of the two handwritten sections via VECTROX
    /// anchors (falling back to calibrated constants).
    ///
    /// - Returns: `(reviewImage, notesImage)` — either may be `nil` if the
    ///   page cannot be rendered or if the crop rect falls outside the image.
    func extractSectionImages(pdfURL: URL) async throws -> (CGImage?, CGImage?) {
        guard let doc = PDFDocument(url: pdfURL) else { return (nil, nil) }
        guard let page = doc.page(at: 0)          else { return (nil, nil) }

        var cgImage = try renderAutoOriented(page: page, scale: 2.0)
        if let obs = try? detectBarcodeObservation(in: cgImage),
           obs.boundingBox.midY < 0.45 {
            cgImage = flipVertical(cgImage) ?? cgImage
        }

        if let v = vectroxDetectRegions(in: cgImage) {
            return (cropCGImage(from: cgImage, rect: v.reviewRect),
                    cropCGImage(from: cgImage, rect: v.notesRect))
        }
        return (cropSection(from: cgImage,
                            topNorm: Self.reviewTopNorm,
                            bottomNorm: Self.reviewBottomNorm),
                cropSection(from: cgImage,
                            topNorm: Self.notesTopNorm,
                            bottomNorm: Self.notesBottomNorm))
    }

    // MARK: - VECTROX: horizontal rule scanner

    /// Scans every pixel row of `cgImage` for dense dark bands (horizontal rule
    /// lines printed by the A4 template generator).
    ///
    /// The image is rendered into an 8-bit grayscale pixel buffer.  A row is
    /// classified as a rule line when ≥ 65 % of the inner 90 % of its pixels
    /// have luminance < 80/255 (≈ 31 % brightness).  Consecutive dark rows are
    /// merged into a single band; the centroid row index is recorded.
    ///
    /// The light gray guide lines drawn inside the section boxes
    /// (RGB 0.8 × alpha 0.6 on white → apparent luminance ≈ 224/255) fall well
    /// above the 80/255 cut-off and are ignored.
    private func vectroxScanHorizontalRules(in cgImage: CGImage) -> [Int] {
        let W = cgImage.width
        let H = cgImage.height
        guard W > 0, H > 0 else { return [] }

        // Render into an 8-bit grayscale pixel buffer (stack-allocated).
        var pixels = [UInt8](repeating: 255, count: W * H)
        guard let ctx = CGContext(
            data: &pixels,
            width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: W,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return [] }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: W, height: H))

        // Inner horizontal span — skip 5 % margin on each side to avoid
        // border artifacts from printing or scanning.
        let lo   = max(0, Int(Double(W) * 0.05))
        let hi   = min(W, Int(Double(W) * 0.95))
        let span = max(1, hi - lo)

        let darkCutoff: UInt8 = 80    // < 31 % luminance → "dark"
        let ruleDensity       = 0.65  // ≥ 65 % of inner span must be dark

        var rules: [Int] = []
        var inBand    = false
        var bandStart = 0

        for row in 0..<H {
            let base = row * W
            var darkCount = 0
            for col in lo..<hi {
                if pixels[base + col] < darkCutoff { darkCount += 1 }
            }
            let density = Double(darkCount) / Double(span)

            if density >= ruleDensity {
                if !inBand { inBand = true; bandStart = row }
            } else if inBand {
                inBand = false
                rules.append((bandStart + row - 1) / 2)   // centroid of band
            }
        }
        if inBand { rules.append((bandStart + H - 1) / 2) }

        return rules   // sorted top-to-bottom (scanned in order)
    }

    // MARK: - VECTROX: internal-rule finder

    /// Scans a horizontal slice of `cgImage` (rows `fromRow` ..< `toRow`) for
    /// the first contiguous band where ≥ 65 % of the inner 90 % of pixels have
    /// luminance **< 128**.
    ///
    /// This "soft-threshold" scan catches lighter gray printed rules (luminance
    /// roughly 80–127) that the main VECTROX pass (cutoff < 80) ignores.
    ///
    /// Primary use: detect the internal border inside the checkbox gap that
    /// separates the Completed row from the "คำถามที่ต้องดู" heading below it.
    ///
    /// - Parameters:
    ///   - cgImage: The full-page CGImage (8-bit is fine; rendered to grayscale
    ///     internally).
    ///   - fromRow: First row to examine (inclusive, in full-image coordinates).
    ///   - toRow:   Last row to examine (exclusive, in full-image coordinates).
    /// - Returns: Centroid row index in full-image coordinates, or `nil` when no
    ///   qualifying band is found.
    private func findInternalRuleRow(in cgImage: CGImage,
                                     fromRow: Int,
                                     toRow: Int) -> Int? {
        let W = cgImage.width
        guard fromRow < toRow, fromRow >= 0, toRow <= cgImage.height, W > 0 else { return nil }

        let sliceH = toRow - fromRow
        guard let slice = cgImage.cropping(to: CGRect(x: 0, y: fromRow,
                                                       width: W, height: sliceH))
        else { return nil }

        var pixels = [UInt8](repeating: 255, count: W * sliceH)
        guard let ctx = CGContext(
            data: &pixels,
            width: W, height: sliceH,
            bitsPerComponent: 8, bytesPerRow: W,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(slice, in: CGRect(x: 0, y: 0, width: W, height: sliceH))

        let lo   = max(0, Int(Double(W) * 0.05))
        let hi   = min(W, Int(Double(W) * 0.95))
        let span = max(1, hi - lo)

        // Soft cutoff: luminance < 128 (≈ 50 % brightness).
        // Catches lighter gray rules while remaining strict enough to skip
        // typical content rows (text, checkbox marks) whose dark pixels are
        // clustered in glyphs rather than spread uniformly across the full width.
        let softCutoff:  UInt8  = 128
        let softDensity: Double = 0.65

        var inBand    = false
        var bandStart = 0

        for row in 0..<sliceH {
            let base = row * W
            var darkCount = 0
            for col in lo..<hi {
                if pixels[base + col] < softCutoff { darkCount += 1 }
            }
            let density = Double(darkCount) / Double(span)

            if density >= softDensity {
                if !inBand { inBand = true; bandStart = row }
            } else if inBand {
                inBand = false
                // Return centroid in full-image row coordinates.
                return fromRow + (bandStart + row - 1) / 2
            }
        }
        if inBand { return fromRow + (bandStart + sliceH - 1) / 2 }
        return nil
    }

    /// Identical scan to `findInternalRuleRow` but returns the centroid of the
    /// **last** qualifying band in the range rather than the first.
    ///
    /// Used to locate the bottom border of a content box (e.g. Additional Notes)
    /// whose bottom rule has luminance in the 80–127 range and is missed by the
    /// main VECTROX pass.
    private func findLastInternalRuleRow(in cgImage: CGImage,
                                         fromRow: Int,
                                         toRow: Int) -> Int? {
        let W = cgImage.width
        guard fromRow < toRow, fromRow >= 0, toRow <= cgImage.height, W > 0 else { return nil }

        let sliceH = toRow - fromRow
        guard let slice = cgImage.cropping(to: CGRect(x: 0, y: fromRow,
                                                       width: W, height: sliceH))
        else { return nil }

        var pixels = [UInt8](repeating: 255, count: W * sliceH)
        guard let ctx = CGContext(
            data: &pixels,
            width: W, height: sliceH,
            bitsPerComponent: 8, bytesPerRow: W,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(slice, in: CGRect(x: 0, y: 0, width: W, height: sliceH))

        let lo   = max(0, Int(Double(W) * 0.05))
        let hi   = min(W, Int(Double(W) * 0.95))
        let span = max(1, hi - lo)

        let softCutoff:  UInt8  = 128
        let softDensity: Double = 0.65

        var lastCentroid: Int? = nil
        var inBand    = false
        var bandStart = 0

        for row in 0..<sliceH {
            let base = row * W
            var darkCount = 0
            for col in lo..<hi {
                if pixels[base + col] < softCutoff { darkCount += 1 }
            }
            let density = Double(darkCount) / Double(span)

            if density >= softDensity {
                if !inBand { inBand = true; bandStart = row }
            } else if inBand {
                inBand = false
                lastCentroid = fromRow + (bandStart + row - 1) / 2
            }
        }
        if inBand { lastCentroid = fromRow + (bandStart + sliceH - 1) / 2 }
        return lastCentroid
    }

    // MARK: - VECTROX: region derivation

    /// Converts the list of detected rule centroids into three crop rectangles
    /// representing the Checkbox strip, Review section, and Notes section.
    ///
    /// **Gap-analysis algorithm:**
    ///   1. Build a gap list between every pair of consecutive rules
    ///      (including virtual boundaries at row 0 and row H).
    ///   2. Keep gaps that are ≥ 2.8 % of image height AND whose top edge is
    ///      below 20 % from the top of the image.
    ///      - Lower bound eliminates 12-pt info-table column-header rows (~24 px)
    ///        while retaining the 32-pt Completed row strip (~64 px).
    ///      - Upper threshold discards the header band and all info-table rows.
    ///   3. The first three surviving gaps (top-to-bottom) are:
    ///      `cg` = checkbox strip, `rg` = review content, `ng` = notes content.
    ///   4. A strict-ascending-height sanity check rejects degenerate results.
    ///   5. Crop rects include the section label by anchoring to `cg.bot` / `rg.bot`
    ///      rather than `rg.top` / `ng.top` (the label gap is too narrow to
    ///      survive the gap filter independently).
    ///
    /// Returns `nil` when fewer than three qualifying gaps are found.
    private func vectroxDetectRegions(in cgImage: CGImage) -> VectroxRegions? {
        let rules = vectroxScanHorizontalRules(in: cgImage)
        guard rules.count >= 2 else { return nil }

        let W = cgImage.width
        let H = cgImage.height

        // Build gap list (boundaries: top-of-image, every rule, bottom-of-image).
        let boundaries = [0] + rules + [H]

        struct Gap { let top: Int; let bot: Int; var height: Int { bot - top } }

        let allGaps = zip(boundaries, boundaries.dropFirst()).map { Gap(top: $0, bot: $1) }

        // Minimum section height: 2.8 % of image height.
        // A4 at 2×: 1684 px → 47 px minimum.
        //   • 12-pt table header row → ~24 px  → excluded ✓
        //   • 32-pt checkbox strip   → ~64 px  → included ✓
        //   • 38-pt label+rule gap   → ~76 px  → included (acceptable; sorted out by position)
        //   • review content         → ~442 px → included ✓
        //   • notes  content         → ~684 px → included ✓
        let minSectionPx = max(40, Int(Double(H) * 0.028))

        // Only look below 20 % from the top — header band and info-table rows
        // are entirely within the upper 25 % of the page.
        let splitRow = Int(Double(H) * 0.20)

        let sectionGaps = allGaps.filter { $0.height >= minSectionPx && $0.top >= splitRow }
        guard sectionGaps.count >= 3 else { return nil }

        let cg = sectionGaps[0]   // checkbox strip
        let rg = sectionGaps[1]   // review content (below label gap)
        let ng = sectionGaps[2]   // notes content  (below label gap)

        // Sanity: checkbox < review < notes (strict ascending).
        // Confirms the three gaps correspond to the expected page structure.
        guard cg.height < rg.height, rg.height < ng.height else { return nil }

        let WF = CGFloat(W)

        // ── Checkbox adjustments ─────────────────────────────────────────────
        // cg.top and cg.bot are the CENTROIDS of the two horizontal rule bands
        // that bound the checkbox gap.  Each rule band is typically 2-4 px wide.
        //
        // IMPORTANT: the checkbox gap [cg.top … cg.bot] contains TWO sub-regions
        // separated by a lighter internal gray rule that the main VECTROX scan
        // (luminance < 80) does NOT detect:
        //
        //   cg.top (~399)  ← main top border (black rule, caught by VECTROX)
        //   ~399–461       ← Completed row content
        //   ~462           ← lighter internal gray rule (luminance ~80–127)
        //   ~469–492       ← "คำถามที่ต้องดู" bold heading
        //   cg.bot (~496)  ← main bottom border (black rule, caught by VECTROX)
        //
        // A secondary soft-threshold scan (luminance < 128, density ≥ 65 %)
        // locates the lighter internal rule and uses it as the crop bottom,
        // producing a pixel-tight crop of ONLY the Completed row.
        let cbUpShift: CGFloat = 2
        let cbTop    = max(0, CGFloat(cg.top) - cbUpShift)

        // Secondary scan: find the lighter internal border within the checkbox gap.
        // Skip the first 15 px below cg.top (the main top rule band) and the
        // last 10 px above cg.bot (the main bottom rule band), so only the
        // interior of the gap is examined.
        let innerRule = findInternalRuleRow(
            in: cgImage,
            fromRow: cg.top + 15,
            toRow:   cg.bot - 10
        )
        // If the internal rule is found: crop ends at its centroid + 3 px
        // (just past the lighter rule line, excluding the Thai heading below).
        // Fallback (no internal rule detected): original cg.bot + 2 behaviour.
        let cbHeight: CGFloat = {
            if let inner = innerRule {
                return CGFloat(inner) + 3 - cbTop
            }
            return CGFloat(cg.bot) - cbTop + 2
        }()

        // ── Review crop geometry ─────────────────────────────────────────────
        //
        // TOP: Anchor to the lighter internal rule (if detected) that forms the
        // top border of the "คำถามที่ต้องดู" section title.  This is the same
        // `innerRule` used for the checkbox crop — it sits ~7 px above the Thai
        // heading text and produces a pixel-tight crop that starts exactly at the
        // section's top border, with no blank whitespace above the title.
        //
        //   Fallback: cg.bot − 60 px when no internal rule is found.
        //
        // BOTTOM: rg.bot + 3 px — the +3 extends past the rule centroid to ensure
        // the full bottom border band is included in the crop (centroids sit in
        // the middle of the ~4 px rule band; cropping to centroid alone clips the
        // lower half of the border line).
        let reviewUpShift: CGFloat = 60   // fallback only
        let reviewTop: CGFloat = {
            if let inner = innerRule {
                return max(0, CGFloat(inner) - 2)   // 2 px above lighter-rule centroid
            }
            return max(0, CGFloat(cg.bot) - reviewUpShift)
        }()
        let reviewBottom: CGFloat = CGFloat(rg.bot) + 3

        // ── Notes crop geometry ──────────────────────────────────────────────
        //
        // TOP: rg.bot − 2 px — starts just above the rule centroid so the full
        // top border of the "Additional Notes" label area is visible.
        //
        // BOTTOM: secondary soft-threshold scan to find the lighter bottom border
        // of the notes content box (luminance 80–127, missed by main VECTROX).
        // Fallback: image bottom (ng.bot) when no such rule is detected.
        let notesTop: CGFloat    = max(0, CGFloat(rg.bot) - 2)
        let notesLastRule        = findLastInternalRuleRow(
            in: cgImage,
            fromRow: ng.top + 50,
            toRow:   ng.bot
        )
        let notesBottom: CGFloat = {
            if let last = notesLastRule {
                return min(CGFloat(cgImage.height), CGFloat(last) + 3)
            }
            return CGFloat(ng.bot)
        }()

        return VectroxRegions(
            // Checkbox strip: full page width — shows "Completed:" label + both
            // checkbox squares + "Practice Paper" and "Timed & Graded" labels.
            checkboxRect: CGRect(
                x: 0, y: cbTop,
                width: WF, height: cbHeight
            ),
            // Review crop: lighter-rule-top → review-content-bottom + 3 px.
            // Starts at the section title's top border; ends past the bottom border.
            reviewRect: CGRect(
                x: 0, y: reviewTop,
                width: WF, height: reviewBottom - reviewTop
            ),
            // Notes crop: just above the top border → detected (or image) bottom.
            notesRect: CGRect(
                x: 0, y: notesTop,
                width: WF, height: notesBottom - notesTop
            )
        )
    }

    // MARK: - Fallback geometry helpers

    /// Returns the checkbox row strip rect using calibrated percentage constants.
    /// Used when VECTROX detection fails.
    private func checkboxRegionRect(for cgImage: CGImage) -> CGRect {
        let W = CGFloat(cgImage.width)
        let H = CGFloat(cgImage.height)
        return CGRect(
            x:      Self.regionXNorm * W,
            y:      Self.regionYNorm * H,
            width:  Self.regionWNorm * W,
            height: Self.regionHNorm * H
        )
    }

    /// Returns a section crop rect using normalised top/bottom percentages.
    /// Used when VECTROX detection fails.
    private func cropSection(from cgImage: CGImage,
                             topNorm: CGFloat,
                             bottomNorm: CGFloat) -> CGImage? {
        let W = CGFloat(cgImage.width)
        let H = CGFloat(cgImage.height)
        let rect = CGRect(
            x:      Self.sectionXNorm * W,
            y:      topNorm * H,
            width:  Self.sectionWNorm * W,
            height: (bottomNorm - topNorm) * H
        )
        return cgImage.cropping(to: rect)
    }

    // MARK: - Half-split density inference

    /// Classifies the paper type by sampling narrow pixel bands centred on the
    /// known X positions of each checkbox square in the template.
    ///
    /// Template geometry (page-normalised X coordinates):
    ///   cb1 Practice Paper  X ≈ 0.175  → in 65 %-wide crop at ~26.9 % of crop W
    ///   cb2 Timed & Graded  X ≈ 0.360  → in 65 %-wide crop at ~55.4 % of crop W
    ///
    /// A ±`cbHalfWindow`-px column band is sampled for each checkbox.  A filled
    /// checkbox (■) produces markedly higher density in its band than an empty
    /// one (□), regardless of adjacent label text.
    private func inferTypeByHalfDensity(in cgImage: CGImage, regionRect: CGRect) -> String? {
        guard let cropped = cgImage.cropping(to: regionRect) else { return nil }
        let w = cropped.width
        let h = cropped.height
        guard w > 1, h > 0 else { return nil }

        guard let graySpace = CGColorSpace(name: CGColorSpace.linearGray),
              let ctx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: w,
                  space: graySpace,
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }

        let buf = data.bindMemory(to: UInt8.self, capacity: w * h)

        // Exact checkbox X centres derived from PDFDocumentGenerator constants
        // (all at 2× render scale, origin at left edge of page = left edge of crop):
        //   margin = 24 pt,  col1x = margin = 24 pt
        //   cb1x = col1x + 80 = 104 pt  →  centre = 104 + 4 = 108 pt = 216 px
        //   cb2x = cb1x + 110 = 214 pt  →  centre = 214 + 4 = 218 pt = 436 px
        //
        // These are absolute pixel positions; since the crop starts at x = 0
        // (same as the page left edge) no conversion is needed.
        let cb1CropNorm = 216.0 / Double(w)   // absolute px → fraction of crop width
        let cb2CropNorm = 436.0 / Double(w)

        // Sample window: ±10 px — tightly wraps the 16 px (8 pt × 2×) checkbox
        // square to avoid contamination from adjacent label text.
        let cbHalfWindow = 10

        func darkCount(centreNorm: Double) -> Int {
            let cx  = Int(Double(w) * centreNorm)
            let lo  = max(0,   cx - cbHalfWindow)
            let hi  = min(w,   cx + cbHalfWindow)
            var cnt = 0
            for row in 0..<h {
                let base = row * w
                for col in lo..<hi {
                    if buf[base + col] < 100 { cnt += 1 }
                }
            }
            return cnt
        }

        let cb1Dark = darkCount(centreNorm: cb1CropNorm)
        let cb2Dark = darkCount(centreNorm: cb2CropNorm)

        let windowArea = Double(cbHalfWindow * 2 * h)
        let cb1Density = Double(cb1Dark) / windowArea
        let cb2Density = Double(cb2Dark) / windowArea

        guard cb1Density >= Self.markDensityFloor ||
              cb2Density >= Self.markDensityFloor else { return nil }

        return cb1Dark >= cb2Dark ? "practice" : "timed"
    }

    // MARK: - Barcode helpers

    private func extractBarcode(from cgImage: CGImage) throws -> String {
        var results: [String] = []
        for _ in 0..<3 {
            if let v = try detectFirstBarcode(in: cgImage) { results.append(v) }
        }
        guard !results.isEmpty else { throw ScanError.noBarcodesFound }
        let unique = Set(results)
        guard unique.count == 1, let confirmed = unique.first else {
            throw ScanError.inconsistentReads(attempts: results)
        }
        return confirmed
    }

    private func detectFirstBarcode(in image: CGImage) throws -> String? {
        let req = VNDetectBarcodesRequest()
        req.symbologies = [.code128]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        return req.results?.compactMap { $0.payloadStringValue }.first
    }

    private func detectBarcodeObservation(in image: CGImage) throws -> VNBarcodeObservation? {
        let req = VNDetectBarcodesRequest()
        req.symbologies = [.code128]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        return req.results?.first { $0.payloadStringValue != nil }
    }

    // MARK: - Crop helper (returns CGImage directly — no NSImage wrapping)

    /// Returns the raw `CGImage` crop.  Callers should display it with
    /// SwiftUI's `Image(decorative: cgImage, scale: 2.0)` to avoid the
    /// NSImage y-axis flip that occurs with `NSImage(cgImage:size:)`.
    private func cropCGImage(from cgImage: CGImage, rect: CGRect) -> CGImage? {
        cgImage.cropping(to: rect)
    }

    // MARK: - CGImage → PNG Data

    /// Encodes a `CGImage` to lossless PNG data for CoreData binary blob storage.
    private func cgImageToPNGData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Orientation corrections

    /// Flips the image vertically (y-axis only, no x-axis change).
    ///
    /// Used to correct the output of `renderPage`, which consistently produces a
    /// y-inverted render (physical page top ends up at image bottom).  A pure
    /// vertical flip restores correct orientation without touching the x-axis, so
    /// text continues to read left-to-right.
    private func flipVertical(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Flips the image horizontally (x-axis only, no y-axis change).
    /// Used as a post-rotation guard when the x-axis remains mirrored after
    /// the center-anchored 180° correction.
    private func flipHorizontal(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// True 180° rotation (flips both x and y axes, center-pivot).
    ///
    /// Reserved for PDF pages that carry `rotation == 180` metadata, where
    /// PDFKit itself rotates the drawn content so the raw render is
    /// horizontally mirrored and a full 180° rotation is the correct inverse.
    private func rotate180(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: .pi)
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Auto-oriented render

    /// Renders the PDF page and applies orientation correction so that the
    /// Completed row (with checkboxes) is always near the top of the returned
    /// CGImage.
    ///
    /// **VECTROX barcode-envelope orientation anchor**
    ///
    /// The printed barcode is always positioned in the page header.  In Vision
    /// coordinates (y = 0 at BOTTOM), an upright barcode has `midY > 0.50`.
    /// If `midY < 0.45` the barcode is near the physical bottom of the image,
    /// meaning the page is upside-down: inject a 180° affine rotation.
    ///
    /// Steps:
    ///   1. `PDFPage.rotation == 180` metadata → immediate flip.
    ///   2. Barcode-envelope midY probe → primary orientation determination.
    ///   3. Last-resort flip (corrected by callers' belt-and-suspenders probe).
    private func renderAutoOriented(page: PDFPage, scale: CGFloat) throws -> CGImage {
        guard let img = renderPage(page, scale: scale) else { throw ScanError.pageRenderFailed }

        // Step 1 — PDF page-rotation metadata (true 180° spin in the PDF itself).
        if page.rotation == 180 { return rotate180(img) ?? img }

        // Step 2 — VECTROX barcode-envelope anchor.
        // renderPage consistently produces a y-inverted image (physical top of the
        // page ends up at image bottom).  Vision coordinates have y = 0 at BOTTOM,
        // so the header barcode — physically at the top — appears at Vision midY
        // near 0.  A vertical-only flip corrects the inversion without mirroring
        // the x-axis (which would make text read backward).
        //
        // Threshold: midY < 0.45 → page is y-inverted → apply flipVertical.
        //            midY ≥ 0.55 → page is upright    → no correction needed.
        //            0.45–0.55   → ambiguous; fall through to last-resort.
        if let obs = try? detectBarcodeObservation(in: img) {
            return obs.boundingBox.midY < 0.45 ? (flipVertical(img) ?? img) : img
        }

        // Step 3 — Last resort: apply vertical flip; belt-and-suspenders re-probe
        // in callers will correct if this guess is wrong.
        return flipVertical(img) ?? img
    }

    // MARK: - Page renderer

    private func renderPage(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let w   = Int(box.width  * scale)
        let h   = Int(box.height * scale)

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)

        // PDF origin is bottom-left; flip y so the physical top maps to image row 0.
        ctx.translateBy(x: 0, y: box.height)
        ctx.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        page.draw(with: .mediaBox, to: ctx)
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }
}
