// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// User-tunable preferences, persisted in `UserDefaults`. Changes post
/// `.settingsChanged` so live components (observer, preview) can react.
final class Settings {
    static let shared = Settings()

    static let changed = Notification.Name("DockPeekSettingsChanged")

    private let defaults = UserDefaults.standard
    private enum Key {
        static let dwell = "dwell"
        static let thumbWidth = "thumbWidth"
        static let disabledBundleIDs = "disabledBundleIDs"
        static let animate = "animate"
    }

    private init() {
        defaults.register(defaults: [
            Key.dwell: 0.25,
            Key.thumbWidth: 240.0,
            Key.animate: true,
        ])
    }

    /// Seconds the cursor must rest on an icon before a preview appears.
    var dwell: TimeInterval {
        get { defaults.double(forKey: Key.dwell) }
        set { defaults.set(newValue, forKey: Key.dwell); post() }
    }

    /// Thumbnail card width in points (height derived from aspect ratio).
    var thumbWidth: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.thumbWidth)) }
        set { defaults.set(Double(newValue), forKey: Key.thumbWidth); post() }
    }

    var animate: Bool {
        get { defaults.bool(forKey: Key.animate) }
        set { defaults.set(newValue, forKey: Key.animate); post() }
    }

    /// Bundle identifiers the user has opted out of previews for.
    var disabledBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledBundleIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.disabledBundleIDs); post() }
    }

    func isEnabled(bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return !disabledBundleIDs.contains(bundleID)
    }

    func setEnabled(_ enabled: Bool, bundleID: String) {
        var set = disabledBundleIDs
        if enabled { set.remove(bundleID) } else { set.insert(bundleID) }
        disabledBundleIDs = set
    }

    private func post() {
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }
}
