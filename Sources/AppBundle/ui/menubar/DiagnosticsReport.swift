import AppKit
import Common

@MainActor
func buildDiagnosticsReport() async -> String {
    nativeSpacesDiagnosticReport()
}

/// Both backends' doctor reports printed these; the fork installer checks them.
@MainActor
func diagnosticsPermissionLines() -> [String] {
    ["Permissions:",
     "  accessibility: \(AXIsProcessTrusted() ? "granted" : "MISSING (required)")",
     "  screen capture: \(CGPreflightScreenCaptureAccess() ? "granted" : "missing (previews and animations use app-icon cards)")"]
}
