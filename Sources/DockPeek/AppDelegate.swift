// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let observer = DockObserver()
    private let preview = PreviewController()
    private var onboarding: OnboardingController?
    private var settingsUI: SettingsController?
    private var statusItem: NSStatusItem?
    private var permissionWatch: Timer?

    private var isRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireObserver()
        startPermissionWatch()

        if PermissionManager.allGranted {
            startObserving()
        } else {
            showOnboarding()
        }
    }

    // MARK: Wiring

    private func wireObserver() {
        observer.onHover = { [weak self] hover in self?.preview.show(for: hover) }
        observer.onHoverEnd = { [weak self] in self?.preview.hide() }
        preview.cursorInPanelChanged = { [weak self] inside in
            self?.observer.setCursorInPanel(inside)
        }
        preview.onDismiss = { [weak self] in self?.observer.reset() }
    }

    private func startObserving() {
        guard !isRunning else { return }
        isRunning = true
        observer.start()
        updateStatusItem()
        showWelcomeIfNeeded()
    }

    /// One-time confirmation the first time previews go live, so the user knows the
    /// (window-less, menu-bar-only) app actually launched after granting permissions.
    private func showWelcomeIfNeeded() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "DockPeek is running"
        alert.informativeText = "Hover any open app in the Dock to preview its windows. "
            + "DockPeek lives in the menu bar — click its icon for preferences or to quit."
        alert.addButton(withTitle: "Got it")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func stopObserving() {
        isRunning = false
        observer.stop()
        preview.hide()
        updateStatusItem()
    }

    // MARK: Permission lifecycle (X4)

    private func startPermissionWatch() {
        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPermissions() }
        }
        RunLoop.main.add(t, forMode: .common)
        permissionWatch = t
    }

    private func checkPermissions() {
        if PermissionManager.allGranted {
            if !isRunning { startObserving() }
        } else if isRunning {
            // Revoked at runtime — pause and let the user re-grant.
            stopObserving()
        }
    }

    private func showOnboarding() {
        let controller = OnboardingController()
        controller.onComplete = { [weak self] in
            guard let self else { return }
            if PermissionManager.allGranted { self.startObserving() }
        }
        onboarding = controller
        controller.present()
    }

    // MARK: Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "dock.rectangle",
                                   accessibilityDescription: "DockPeek")
            button.image?.isTemplate = true
        }
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        let menu = NSMenu()

        let status = NSMenuItem(
            title: PermissionManager.allGranted
                ? (isRunning ? "DockPeek: On" : "DockPeek: Paused")
                : "DockPeek: Needs permission",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if PermissionManager.allGranted {
            let toggle = NSMenuItem(title: isRunning ? "Pause Previews" : "Resume Previews",
                                    action: #selector(togglePreviews), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
        } else {
            let fix = NSMenuItem(title: "Grant Permissions…",
                                 action: #selector(openOnboarding), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openSettings),
                               keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DockPeek", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func togglePreviews() { isRunning ? stopObserving() : startObserving() }
    @objc private func openOnboarding() { showOnboarding() }

    @objc private func openSettings() {
        let ui = settingsUI ?? SettingsController()
        settingsUI = ui
        ui.present()
    }

    @objc private func toggleLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        updateStatusItem()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
