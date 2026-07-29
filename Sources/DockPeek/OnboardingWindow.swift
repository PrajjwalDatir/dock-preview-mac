// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// A friendly welcome window that explains *why* DockPeek needs Accessibility and
/// Screen Recording before it triggers the scary-looking system prompts. Successful
/// utilities front-load this context so users click "Allow" instead of "Deny".
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var accessibilityRow: PermissionRow?
    private var screenRow: PermissionRow?
    private var refreshTimer: Timer?

    /// Called once both permissions are granted (or when the user closes the window).
    var onComplete: (() -> Void)?

    func present() {
        if window != nil { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to DockPeek"
        win.delegate = self
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = buildContent()
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        // Re-check permissions periodically so the rows update live as the user
        // flips the switches in System Settings.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop synchronously onto the main actor.
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
        refreshStatus()
    }

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 470))

        let title = NSTextField(labelWithString: "See window previews from your Dock")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.frame = NSRect(x: 30, y: 410, width: 400, height: 30)
        root.addSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Hover any running app in the Dock and DockPeek shows a live preview of its windows — just like the taskbar on Windows. To do that it needs two one-time permissions:")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 30, y: 340, width: 400, height: 60)
        root.addSubview(subtitle)

        let accRow = PermissionRow(
            title: "Accessibility",
            reason: "Reads which Dock icon your cursor is over and where it sits on screen. DockPeek never types or clicks for you.",
            buttonTitle: "Enable…",
            y: 240
        )
        accRow.onButton = { [weak self] in
            PermissionManager.requestAccessibility(prompt: true)
            PermissionManager.openSettings(.accessibility)
            self?.refreshStatus()
        }
        root.addSubview(accRow)
        accessibilityRow = accRow

        let scrRow = PermissionRow(
            title: "Screen Recording",
            reason: "Grabs a picture of the app's windows to build the thumbnail. Nothing is ever recorded, saved, or sent anywhere — it stays on your Mac.",
            buttonTitle: "Enable…",
            y: 130
        )
        scrRow.onButton = { [weak self] in
            PermissionManager.requestScreenRecording()
            PermissionManager.openSettings(.screenRecording)
            self?.refreshStatus()
        }
        root.addSubview(scrRow)
        screenRow = scrRow

        let note = NSTextField(wrappingLabelWithString:
            "You only approve these once. DockPeek then runs quietly in the menu bar. Screen Recording may need one relaunch to take effect.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.frame = NSRect(x: 30, y: 46, width: 280, height: 60)
        root.addSubview(note)

        let relaunch = NSButton(title: "Relaunch", target: self, action: #selector(relaunchApp))
        relaunch.bezelStyle = .rounded
        relaunch.frame = NSRect(x: 324, y: 30, width: 100, height: 28)
        relaunch.toolTip = "Relaunch DockPeek so a just-granted Screen Recording permission takes effect."
        root.addSubview(relaunch)

        return root
    }

    /// Accessibility & Screen Recording are only re-evaluated at launch, so a fresh
    /// process is the reliable way to pick up a just-granted permission.
    @objc private func relaunchApp() {
        Relauncher.relaunch()
    }

    private func refreshStatus() {
        accessibilityRow?.setGranted(PermissionManager.hasAccessibility)
        screenRow?.setGranted(PermissionManager.hasScreenRecording)
        if PermissionManager.allGranted {
            refreshTimer?.invalidate()
            refreshTimer = nil
            onComplete?()
        }
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        window = nil
        onComplete?()
    }
}

/// One permission line: title, explanation, a status pill and an "Enable…" button.
final class PermissionRow: NSView {
    var onButton: (() -> Void)?
    private let statusLabel = NSTextField(labelWithString: "Not granted")
    private let button: NSButton

    init(title: String, reason: String, buttonTitle: String, y: CGFloat) {
        button = NSButton(title: buttonTitle, target: nil, action: nil)
        super.init(frame: NSRect(x: 30, y: y, width: 400, height: 90))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.frame = NSRect(x: 14, y: 60, width: 240, height: 20)
        addSubview(name)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.frame = NSRect(x: 14, y: 60, width: 372, height: 20)
        statusLabel.alignment = .right
        addSubview(statusLabel)

        let reasonLabel = NSTextField(wrappingLabelWithString: reason)
        reasonLabel.font = .systemFont(ofSize: 11)
        reasonLabel.textColor = .secondaryLabelColor
        reasonLabel.frame = NSRect(x: 14, y: 12, width: 280, height: 44)
        addSubview(reasonLabel)

        button.bezelStyle = .rounded
        button.frame = NSRect(x: 300, y: 20, width: 86, height: 28)
        button.target = self
        button.action = #selector(tapped)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onButton?() }

    func setGranted(_ granted: Bool) {
        statusLabel.stringValue = granted ? "✓ Granted" : "Not granted"
        statusLabel.textColor = granted ? .systemGreen : .systemOrange
        button.isHidden = granted
    }
}
