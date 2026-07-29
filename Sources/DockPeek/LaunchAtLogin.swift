// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` for registering DockPeek as a login item.
/// Works for ad-hoc–signed bundles as long as the app lives at a stable path.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("DockPeek: launch-at-login toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
