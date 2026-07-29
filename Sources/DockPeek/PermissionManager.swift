// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import ApplicationServices
import CoreGraphics

/// Centralises the two privacy permissions DockPeek needs:
///
///  1. **Accessibility** (`AXIsProcessTrusted`) — to read the Dock's element tree
///     and find which icon the mouse is hovering over, plus its on-screen frame.
///  2. **Screen Recording** (`CGPreflightScreenCaptureAccess`) — to capture the
///     live window thumbnails shown in the preview.
///
/// Neither permission can be toggled programmatically; the OS only lets us *ask*.
/// The user grants each one once in System Settings and it sticks for this app.
enum PermissionManager {

    // MARK: Accessibility

    /// True if the app is already trusted for Accessibility.
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Ask for Accessibility. Passing `prompt: true` shows the system dialog that
    /// deep-links the user into System Settings › Privacy & Security › Accessibility.
    @discardableResult
    static func requestAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Screen Recording

    /// True if we already hold Screen Recording permission.
    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Trigger the native "wants to record the screen" prompt. Returns the current
    /// (pre-grant) status; the grant itself only takes effect after the user
    /// relaunches, which is standard macOS behaviour for Screen Recording.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    // MARK: Convenience

    static var allGranted: Bool {
        hasAccessibility && hasScreenRecording
    }

    /// Open a specific pane of System Settings › Privacy & Security.
    static func openSettings(_ pane: SettingsPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    enum SettingsPane {
        case accessibility
        case screenRecording

        var urlString: String {
            switch self {
            case .accessibility:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .screenRecording:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            }
        }
    }
}
