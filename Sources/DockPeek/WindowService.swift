// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import ScreenCaptureKit

/// A single captured window belonging to the hovered app.
struct WindowThumbnail: Identifiable {
    let id: CGWindowID
    let title: String
    let image: NSImage
    /// Pixel aspect ratio (w/h), used to size the card.
    let aspect: CGFloat
}

/// Enumerates and captures the on-screen windows of a process using
/// ScreenCaptureKit (the modern, non-deprecated capture path). A small
/// time-boxed cache avoids re-capturing when the user re-hovers quickly.
enum WindowService {

    private struct CacheEntry {
        let image: NSImage
        let aspect: CGFloat
        let time: Date
    }

    private static var cache: [CGWindowID: CacheEntry] = [:]
    private static let cacheTTL: TimeInterval = 1.5
    private static let lock = NSLock()

    /// Capture (snapshot) every real, on-screen window owned by `pid`.
    /// Off the main thread; results returned when ready.
    static func thumbnails(for pid: pid_t) async -> [WindowThumbnail] {
        let maxWidth = Int(max(160, Settings.shared.thumbWidth) * 2) // ~2x for Retina
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            let windows = content.windows.filter { win in
                win.owningApplication?.processID == pid
                    && win.isOnScreen
                    && win.windowLayer == 0
                    && win.frame.width > 40 && win.frame.height > 40
            }
            // Front-to-back stays as SCK returns it (front first).
            var results: [WindowThumbnail] = []
            for win in windows {
                let title = (win.title?.isEmpty == false)
                    ? win.title!
                    : (win.owningApplication?.applicationName ?? "Window")

                if let cached = cachedThumb(for: win.windowID) {
                    results.append(WindowThumbnail(id: win.windowID, title: title,
                                                   image: cached.image, aspect: cached.aspect))
                    continue
                }
                guard let (image, aspect) = await capture(win, maxPixelWidth: maxWidth) else { continue }
                store(image: image, aspect: aspect, for: win.windowID)
                results.append(WindowThumbnail(id: win.windowID, title: title,
                                               image: image, aspect: aspect))
            }
            return results
        } catch {
            return []
        }
    }

    private static func capture(_ window: SCWindow, maxPixelWidth: Int) async -> (NSImage, CGFloat)? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = max(1.0, window.frame.width / CGFloat(maxPixelWidth))
        config.width = max(1, Int(window.frame.width / scale))
        config.height = max(1, Int(window.frame.height / scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        do {
            let cg = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
            let aspect = CGFloat(cg.width) / CGFloat(max(1, cg.height))
            let size = NSSize(width: CGFloat(cg.width) / 2.0, height: CGFloat(cg.height) / 2.0)
            return (NSImage(cgImage: cg, size: size), aspect)
        } catch {
            return nil
        }
    }

    // MARK: Cache

    private static func cachedThumb(for id: CGWindowID) -> CacheEntry? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[id], Date().timeIntervalSince(entry.time) < cacheTTL else {
            return nil
        }
        return entry
    }

    private static func store(image: NSImage, aspect: CGFloat, for id: CGWindowID) {
        lock.lock(); defer { lock.unlock() }
        cache[id] = CacheEntry(image: image, aspect: aspect, time: Date())
        // Trim opportunistically.
        if cache.count > 64 {
            let cutoff = Date().addingTimeInterval(-cacheTTL)
            cache = cache.filter { $0.value.time > cutoff }
        }
    }
}
