// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Sparkle

/// Wraps Sparkle's standard updater controller so the rest of the app can trigger
/// "Check for Updates…" and validate the menu item without importing Sparkle.
///
/// The updater is configured entirely through Info.plist (`SUFeedURL`,
/// `SUPublicEDKey`, `SUEnableAutomaticChecks`): it checks a signed appcast, and
/// only installs updates whose EdDSA signature matches our embedded public key.
@MainActor
final class UpdaterController: NSObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    private override init() {
        // startingUpdater: true begins periodic background checks immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        super.init()
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    @objc func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
