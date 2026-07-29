// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

// DockPeek runs as a background/menu-bar (accessory) app: no Dock icon of its own,
// just a status-bar item. The AppDelegate wires up permissions, the Dock hover
// observer and the preview panel.
//
// `app.run()` blocks here for the lifetime of the process, so keeping `delegate`
// in this scope holds the strong reference that NSApplication.delegate does not.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
