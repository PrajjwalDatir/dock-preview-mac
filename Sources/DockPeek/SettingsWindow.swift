// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Preferences window: dwell delay, thumbnail size, animation, launch-at-login,
/// and a per-app on/off list for currently running apps.
@MainActor
final class SettingsController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let settings = Settings.shared

    private var dwellLabel: NSTextField?
    private var sizeLabel: NSTextField?

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 470),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        win.title = "DockPeek Preferences"
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = buildContent()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 470))

        // Hover delay
        let dwellTitle = label("Hover delay", size: 13, weight: .semibold,
                               frame: NSRect(x: 24, y: 424, width: 200, height: 18))
        root.addSubview(dwellTitle)

        let dwellSlider = NSSlider(value: settings.dwell, minValue: 0.0, maxValue: 1.0,
                                   target: self, action: #selector(dwellChanged))
        dwellSlider.frame = NSRect(x: 24, y: 396, width: 300, height: 20)
        root.addSubview(dwellSlider)

        let dl = label(dwellText(settings.dwell), size: 12, weight: .regular,
                       frame: NSRect(x: 332, y: 396, width: 70, height: 18))
        dl.textColor = .secondaryLabelColor
        root.addSubview(dl)
        dwellLabel = dl

        // Thumbnail size
        let sizeTitle = label("Thumbnail size", size: 13, weight: .semibold,
                              frame: NSRect(x: 24, y: 356, width: 200, height: 18))
        root.addSubview(sizeTitle)

        let sizeSlider = NSSlider(value: Double(settings.thumbWidth), minValue: 160, maxValue: 360,
                                  target: self, action: #selector(sizeChanged))
        sizeSlider.frame = NSRect(x: 24, y: 328, width: 300, height: 20)
        root.addSubview(sizeSlider)

        let sl = label("\(Int(settings.thumbWidth)) pt", size: 12, weight: .regular,
                       frame: NSRect(x: 332, y: 328, width: 70, height: 18))
        sl.textColor = .secondaryLabelColor
        root.addSubview(sl)
        sizeLabel = sl

        // Toggles
        let animate = NSButton(checkboxWithTitle: "Animate previews", target: self,
                               action: #selector(animateChanged))
        animate.state = settings.animate ? .on : .off
        animate.frame = NSRect(x: 24, y: 292, width: 300, height: 20)
        root.addSubview(animate)

        let login = NSButton(checkboxWithTitle: "Launch DockPeek at login", target: self,
                             action: #selector(loginChanged))
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        login.frame = NSRect(x: 24, y: 264, width: 300, height: 20)
        root.addSubview(login)

        // Per-app list
        let appsTitle = label("Show previews for", size: 13, weight: .semibold,
                              frame: NSRect(x: 24, y: 228, width: 300, height: 18))
        root.addSubview(appsTitle)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 24, width: 372, height: 196))
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 4
        list.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        list.translatesAutoresizingMaskIntoConstraints = false

        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        var seen = Set<String>()
        for app in runningApps {
            guard let bid = app.bundleIdentifier, seen.insert(bid).inserted else { continue }
            let cb = NSButton(checkboxWithTitle: app.localizedName ?? bid,
                              target: self, action: #selector(appToggled(_:)))
            cb.state = settings.isEnabled(bundleID: bid) ? .on : .off
            cb.identifier = NSUserInterfaceItemIdentifier(bid)
            list.addArrangedSubview(cb)
        }

        let clip = NSClipView()
        clip.documentView = list
        scroll.contentView = clip
        list.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -20).isActive = true
        root.addSubview(scroll)

        return root
    }

    // MARK: Actions

    @objc private func dwellChanged(_ sender: NSSlider) {
        settings.dwell = sender.doubleValue
        dwellLabel?.stringValue = dwellText(sender.doubleValue)
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        settings.thumbWidth = CGFloat(sender.doubleValue.rounded())
        sizeLabel?.stringValue = "\(Int(sender.doubleValue.rounded())) pt"
    }

    @objc private func animateChanged(_ sender: NSButton) {
        settings.animate = (sender.state == .on)
    }

    @objc private func loginChanged(_ sender: NSButton) {
        let ok = LaunchAtLogin.set(sender.state == .on)
        if !ok { sender.state = LaunchAtLogin.isEnabled ? .on : .off }
    }

    @objc private func appToggled(_ sender: NSButton) {
        guard let bid = sender.identifier?.rawValue else { return }
        settings.setEnabled(sender.state == .on, bundleID: bid)
    }

    func windowWillClose(_ notification: Notification) { window = nil }

    // MARK: Helpers

    private func dwellText(_ v: Double) -> String {
        v < 0.03 ? "Instant" : String(format: "%.2f s", v)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight,
                       frame: NSRect) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.frame = frame
        return l
    }
}
