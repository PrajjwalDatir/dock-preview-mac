// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import ApplicationServices

/// Where the Dock lives on the screen the icon is on.
enum DockOrientation {
    case bottom, left, right
}

/// A Dock icon the mouse is over, resolved to a running app.
struct DockItemHover: Equatable {
    let title: String
    let bundleID: String?
    /// Icon frame in Cocoa (bottom-left origin) global screen coordinates.
    let iconFrame: CGRect
    let pid: pid_t
    let orientation: DockOrientation

    static func == (lhs: DockItemHover, rhs: DockItemHover) -> Bool {
        lhs.pid == rhs.pid && lhs.iconFrame.integral == rhs.iconFrame.integral
    }
}

/// Watches the Dock and reports which application icon the cursor is dwelling on.
///
/// We can't safely hook `com.apple.dock`, so we drive off global mouse-move events
/// (cheap — nothing fires while the cursor is still) and ask the system-wide
/// Accessibility element at the cursor. When that element is an `AXDockItem` we read
/// its title / URL / frame, resolve the URL to a *running* application, and, after a
/// short dwell, emit `onHover`.
final class DockObserver {

    var onHover: ((DockItemHover) -> Void)?
    var onHoverEnd: (() -> Void)?

    private let systemWide = AXUIElementCreateSystemWide()
    private var monitor: Any?

    private var dwellTimer: Timer?
    private var hideTimer: Timer?
    private var pendingTarget: DockItemHover?
    private var shownTarget: DockItemHover?
    private var cursorInPanel = false

    private var dwell: TimeInterval { Settings.shared.dwell }
    private let hideGrace: TimeInterval = 0.20

    // MARK: Lifecycle

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouse(NSEvent.mouseLocation)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cancelDwell()
        cancelHide()
        pendingTarget = nil
        shownTarget = nil
    }

    /// Clear all hover state (after Esc / click-to-raise) so re-hovering the same
    /// icon triggers a fresh preview.
    func reset() {
        cancelDwell()
        cancelHide()
        pendingTarget = nil
        shownTarget = nil
        cursorInPanel = false
    }

    /// Called by the preview controller via tracking areas so the panel doesn't
    /// dismiss while the cursor is inside it.
    func setCursorInPanel(_ inside: Bool) {
        cursorInPanel = inside
        if inside {
            cancelHide()
        } else {
            scheduleHide()
        }
    }

    // MARK: Mouse handling

    private func handleMouse(_ cocoa: CGPoint) {
        if cursorInPanel { return }

        guard let target = dockItem(atCocoaPoint: cocoa) else {
            // Not over a previewable icon.
            pendingTarget = nil
            cancelDwell()
            if shownTarget != nil { scheduleHide() }
            return
        }

        // Already showing this icon → keep it.
        if target == shownTarget {
            cancelHide()
            return
        }

        // New candidate → (re)start the dwell timer.
        if target != pendingTarget {
            pendingTarget = target
            cancelHide()
            cancelDwell()
            let d = dwell
            let t = Timer(timeInterval: d, repeats: false) { [weak self] _ in
                guard let self, let pending = self.pendingTarget else { return }
                self.shownTarget = pending
                self.pendingTarget = nil
                self.onHover?(pending)
            }
            RunLoop.main.add(t, forMode: .common)
            dwellTimer = t
        }
    }

    private func scheduleHide() {
        cancelHide()
        let t = Timer(timeInterval: hideGrace, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.shownTarget = nil
            self.pendingTarget = nil
            self.onHoverEnd?()
        }
        RunLoop.main.add(t, forMode: .common)
        hideTimer = t
    }

    private func cancelDwell() { dwellTimer?.invalidate(); dwellTimer = nil }
    private func cancelHide() { hideTimer?.invalidate(); hideTimer = nil }

    // MARK: Accessibility hit-testing

    private func dockItem(atCocoaPoint cocoa: CGPoint) -> DockItemHover? {
        let primaryHeight = CoordinateSpace.primaryHeight
        let axPoint = CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)

        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(axPoint.x), Float(axPoint.y), &elementRef
        ) == .success, let element = elementRef else { return nil }

        guard axString(element, kAXRoleAttribute) == "AXDockItem" else { return nil }
        if let subrole = axString(element, kAXSubroleAttribute),
           subrole != "AXApplicationDockItem" { return nil }

        guard let frameAX = axFrame(element) else { return nil }

        // Resolve to a running app: prefer the item's URL (robust against
        // duplicate names), fall back to matching the title.
        guard let app = runningApp(for: element) else { return nil }
        guard Settings.shared.isEnabled(bundleID: app.bundleIdentifier) else { return nil }

        let cocoaFrame = CGRect(
            x: frameAX.origin.x,
            y: primaryHeight - frameAX.origin.y - frameAX.height,
            width: frameAX.width, height: frameAX.height
        )

        return DockItemHover(
            title: app.localizedName ?? axString(element, kAXTitleAttribute) ?? "App",
            bundleID: app.bundleIdentifier,
            iconFrame: cocoaFrame,
            pid: app.processIdentifier,
            orientation: orientation(for: cocoaFrame)
        )
    }

    private func runningApp(for element: AXUIElement) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications

        // 1) By the Dock item's URL → bundle identifier.
        var urlRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success,
           let url = urlRef as? URL,
           let bundleID = Bundle(url: url)?.bundleIdentifier {
            if let match = apps.first(where: {
                $0.activationPolicy == .regular && $0.bundleIdentifier == bundleID
            }) {
                return match
            }
        }

        // 2) Fall back to the visible title.
        if let title = axString(element, kAXTitleAttribute) {
            return apps.first {
                $0.activationPolicy == .regular && $0.localizedName == title
            }
        }
        return nil
    }

    /// Infer Dock position from the icon's placement on its screen.
    private func orientation(for iconFrame: CGRect) -> DockOrientation {
        let screen = NSScreen.screens.first { $0.frame.intersects(iconFrame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame, let full = screen?.frame else { return .bottom }
        let leftGap = iconFrame.minX - full.minX
        let rightGap = full.maxX - iconFrame.maxX
        // A side Dock sits flush to a screen edge with the other edge far away.
        if leftGap < 4 && rightGap > visible.width * 0.3 { return .left }
        if rightGap < 4 && leftGap > visible.width * 0.3 { return .right }
        return .bottom
    }

    // MARK: AX helpers

    private func axString(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, CFGetTypeID(posValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}

/// Converts between Cocoa (bottom-left) and Quartz/AX (top-left) global coords.
enum CoordinateSpace {
    static var primaryHeight: CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return NSScreen.main?.frame.height ?? 0
    }
}
