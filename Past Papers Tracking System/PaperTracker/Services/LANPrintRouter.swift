import Foundation

// MARK: - WindowsPrintMode

/// Determines which endpoint on the Windows print server is targeted and
/// whether macOS Screen Sharing is launched after a successful transfer.
enum WindowsPrintMode {
    /// POST to /print-default.  The Windows server spools directly via
    /// PowerShell system defaults.  Screen Sharing is NOT opened.
    case expressDefault

    /// POST to /print-manual.  The Windows server opens the PDF in Brave
    /// Browser and sends Ctrl+Shift+P to trigger the native print dialog.
    /// Screen Sharing IS opened on the Mac side after a successful transfer
    /// so the user can interact with the Windows print dialog remotely.
    case manualWithVNC

    var endpoint: String {
        switch self {
        case .expressDefault: return "/print-default"
        case .manualWithVNC:  return "/print-manual"
        }
    }
}

// MARK: - LANPrintRouter

/// Routes PDF data to the Windows PC print server over the local area network.
///
/// The Windows PC must be running `win_print_server.py`.
///
/// Configuration is stored in `UserDefaults`:
///   - `lanPrintWindowsIP`  — "192.168.1.70:8999"  (host:port string)
enum LANPrintRouter {

    // MARK: UserDefaults key

    static let ipPortKey = "lanPrintWindowsIP"

    // MARK: - Routing

    /// POST raw PDF `data` to the Windows server using the specified `mode`.
    ///
    /// - `.expressDefault` → `/print-default`  (no VNC)
    /// - `.manualWithVNC`  → `/print-manual`   (VNC opened on success)
    ///
    /// - Parameter targetPrinter: When non-nil, sent as the `X-Target-Printer`
    ///   HTTP header so the Windows server can spool directly to a named driver
    ///   instead of the system default.  Pass `nil` to use the Windows default.
    ///
    /// Throws `LPRError.noIPConfigured` when no address has been saved.
    /// Throws `LPRError.serverError` when the server returns a non-200 status.
    static func sendToWindows(
        data: Data,
        filename: String,
        mode: WindowsPrintMode,
        targetPrinter: String? = nil
    ) async throws {
        guard let ipPort = UserDefaults.standard.string(forKey: ipPortKey),
              !ipPort.isEmpty else { throw LPRError.noIPConfigured }
        guard let url = URL(string: "http://\(ipPort)\(mode.endpoint)") else {
            throw LPRError.badURL
        }
        var req = URLRequest(url: url, timeoutInterval: 60)   // 60 s — headroom for large PDFs
        req.httpMethod = "POST"
        req.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        req.setValue(filename,          forHTTPHeaderField: "X-Filename")
        if let printer = targetPrinter, !printer.isEmpty {
            req.setValue(printer, forHTTPHeaderField: "X-Target-Printer")
        }
        let (_, resp) = try await URLSession.shared.upload(for: req, from: data)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw LPRError.serverError
        }
        if mode == .manualWithVNC {
            let ip = ipPort.components(separatedBy: ":").first ?? ipPort
            launchScreenSharing(ip: ip)
        }
    }

    // MARK: - Connection test

    /// Returns `true` if the server at `ipPort` responds to GET /status within 3 s.
    static func testConnection(ipPort: String) async -> Bool {
        guard let url = URL(string: "http://\(ipPort)/status") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "GET"
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    // MARK: - Printer enumeration

    /// Fetches the list of installed printer names from the Windows server's
    /// GET /printers endpoint.
    ///
    /// - Throws: URL / network errors when the server is unreachable, or
    ///   `LPRError.serverError` when the response cannot be decoded.
    ///   Callers can use this to distinguish "server down" from "server
    ///   returned an empty list" (e.g. pywin32 not installed).
    static func fetchPrinters(ipPort: String) async throws -> [String] {
        guard let url = URL(string: "http://\(ipPort)/printers") else { throw LPRError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "GET"
        let (data, resp) = try await URLSession.shared.data(for: req)   // throws on network error
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 {
            // Old win_print_server.py (≤ v2.0) doesn't have /printers.
            throw LPRError.endpointNotFound
        }
        guard status == 200 else { throw LPRError.serverError }
        guard let names = try? JSONDecoder().decode([String].self, from: data) else {
            throw LPRError.serverError
        }
        return names
    }

    // MARK: - Screen Sharing

    /// Opens Apple's built-in Screen Sharing app targeting `ip` via the vnc:// scheme.
    static func launchScreenSharing(ip: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments     = ["vnc://\(ip)"]
        try? p.run()
    }
}

// MARK: - LPRError

enum LPRError: LocalizedError {
    case noIPConfigured
    case badURL
    case endpointNotFound   // server is old (≤ v2.0), /printers doesn't exist
    case serverError        // server returned 5xx or undecodable body

    var errorDescription: String? {
        switch self {
        case .noIPConfigured:
            return "Windows PC address not set — configure it in Settings."
        case .badURL:
            return "Invalid Windows PC address format (expected host:port)."
        case .endpointNotFound:
            return "Server returned 404 — update win_print_server.py to v2.1 on the Windows PC."
        case .serverError:
            return "Server returned an error — check the win_print_server.py console for details."
        }
    }
}
