import Foundation

/// Moves a scanned PDF into a flat subject-named directory under the archive root.
///
/// Flat-namespace rule: no nesting below the subject folder.
/// Final path: `<archiveRoot>/<subjectName>/<barcodeValue>.pdf`
struct FileOrganizationPipeline {

    enum PipelineError: LocalizedError {
        case subjectDirectoryCreationFailed(Error)
        case moveItemFailed(Error)

        var errorDescription: String? {
            switch self {
            case .subjectDirectoryCreationFailed(let e): return "Could not create subject directory: \(e.localizedDescription)"
            case .moveItemFailed(let e):                 return "Could not move file: \(e.localizedDescription)"
            }
        }
    }

    /// Organises `sourceURL` and returns the final destination URL.
    @discardableResult
    static func organize(
        sourceURL: URL,
        subjectName: String,
        barcodeValue: String,
        archiveRoot: URL
    ) throws -> URL {
        let fm = FileManager.default

        let subjectDir = archiveRoot.appending(component: subjectName, directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: subjectDir, withIntermediateDirectories: true)
        } catch {
            throw PipelineError.subjectDirectoryCreationFailed(error)
        }

        let destination = subjectDir.appending(component: "\(barcodeValue).pdf")

        // Idempotent: remove a stale copy if this is a re-scan.
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            try? fm.removeItem(at: destination)
        }

        do {
            try fm.moveItem(at: sourceURL, to: destination)
        } catch {
            throw PipelineError.moveItemFailed(error)
        }

        return destination
    }

    /// Returns the URL that `organize` would produce without moving anything.
    static func expectedURL(subjectName: String, barcodeValue: String, archiveRoot: URL) -> URL {
        archiveRoot
            .appending(component: subjectName, directoryHint: .isDirectory)
            .appending(component: "\(barcodeValue).pdf")
    }
}
