// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import ApplicationServices
import SwiftUI

/// Owns the floating preview panel: builds thumbnail cards, sizes and positions the
/// panel relative to the hovered Dock icon (bottom / left / right Dock), animates it
/// in, and handles click-to-raise and Esc-to-dismiss.
@MainActor
final class PreviewController {

    /// Notifies the observer when the cursor enters/leaves the panel so it won't
    /// dismiss while the user is interacting with the preview.
    var cursorInPanelChanged: ((Bool) -> Void)?
    /// Asked to dismiss (Esc, or click-to-raise) so the observer resets its state.
    var onDismiss: (() -> Void)?

    private let panel: PreviewPanel
    private let backdrop: NSVisualEffectView
    private let content = NSView()

    private var generation = 0
    private var escMonitor: Any?

    // Layout constants (points).
    private let thumbHeight: CGFloat = 150
    private let padding: CGFloat = 12
    private let spacing: CGFloat = 12
    private let headerHeight: CGFloat = 20
    private let labelHeight: CGFloat = 16
    private let iconGap: CGFloat = 12
    private let notch: CGFloat = 9

    init() {
        panel = PreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))

        backdrop = NSVisualEffectView()
        backdrop.material = .popover        // adapts to Reduce Transparency automatically
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active

        let root = TrackingView()
        root.autoresizingMask = [.width, .height]
        root.addSubview(backdrop)
        root.addSubview(content)
        root.onCursor = { [weak self] inside in self?.cursorInPanelChanged?(inside) }
        panel.contentView = root
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: Show / hide

    func show(for hover: DockItemHover) {
        generation += 1
        let token = generation
        let pid = hover.pid

        Task { @MainActor in
            let thumbs = await WindowService.thumbnails(for: pid)
            guard token == self.generation else { return }          // cursor moved on
            guard NSRunningApplication(processIdentifier: pid) != nil else { return }
            guard !thumbs.isEmpty else { self.hide(); return }       // empty-state: nothing to show
            self.render(hover: hover, thumbs: thumbs)
        }
    }

    func hide() {
        generation += 1
        removeEscMonitor()
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        content.subviews.forEach { $0.removeFromSuperview() }
    }

    // MARK: Rendering

    private func render(hover: DockItemHover, thumbs: [WindowThumbnail]) {
        content.subviews.forEach { $0.removeFromSuperview() }

        let cardW = max(160, Settings.shared.thumbWidth)
        let count = thumbs.count

        // Cap width to max 4 items, scroll the rest
        let visibleCount = min(count, 4)
        let cardsWidth = CGFloat(visibleCount) * cardW + CGFloat(visibleCount - 1) * spacing
        let cardBlockH = thumbHeight + 4 + labelHeight
        let bodyWidth = max(cardsWidth, 200) + padding * 2
        let bodyHeight = padding + headerHeight + 8 + cardBlockH + padding

        let onBottom = hover.orientation == .bottom
        let panelWidth = bodyWidth + (onBottom ? 0 : notch)
        let panelHeight = bodyHeight + (onBottom ? notch : 0)

        // Body origin inside the panel (leave room for the notch on the icon side).
        let bodyOrigin = CGPoint(
            x: hover.orientation == .left ? notch : 0,
            y: onBottom ? notch : 0
        )

        let hostView = NSHostingView(rootView: ThumbsView(
            hover: hover,
            thumbs: thumbs,
            cardW: cardW,
            thumbHeight: thumbHeight,
            onRaise: { [weak self] thumb in self?.raise(thumb) },
            onClose: { [weak self] thumb in self?.performWindowAction(thumb: thumb, actionAttribute: kAXCloseButtonAttribute as CFString) },
            onMinimize: { [weak self] thumb in self?.performWindowAction(thumb: thumb, actionAttribute: kAXMinimizeButtonAttribute as CFString) }
        ))

        hostView.frame = NSRect(
            x: bodyOrigin.x,
            y: bodyOrigin.y,
            width: bodyWidth,
            height: bodyHeight
        )
        content.addSubview(hostView)

        // Position the whole panel on screen.
        let size = NSSize(width: panelWidth, height: panelHeight)
        let origin = position(for: size, over: hover.iconFrame, orientation: hover.orientation)
        let frame = NSRect(origin: origin, size: size)

        // Backdrop masked to a rounded rect + notch pointing at the icon.
        backdrop.frame = NSRect(origin: .zero, size: size)
        backdrop.maskImage = Self.maskImage(size: size, bodyOrigin: bodyOrigin,
                                            bodySize: NSSize(width: bodyWidth, height: bodyHeight),
                                            orientation: hover.orientation,
                                            iconCenterX: hover.iconFrame.midX - origin.x,
                                            iconCenterY: hover.iconFrame.midY - origin.y,
                                            notch: notch)

        let wasVisible = panel.isVisible
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        installEscMonitor()

        // Animate only on first appearance (flicker-free when swapping icons).
        if !wasVisible && Settings.shared.animate
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animateIn()
        } else {
            panel.alphaValue = 1
        }
    }

    private func animateIn() {
        // Fade in only — a transform scale on the content layer would need
        // anchorPoint/position compensation and risks a positional jog. A quick
        // opacity fade reads cleanly and never mispositions the panel.
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    // MARK: Positioning

    private func position(for size: NSSize, over icon: CGRect,
                          orientation: DockOrientation) -> CGPoint {
        var x: CGFloat
        var y: CGFloat
        switch orientation {
        case .bottom:
            x = icon.midX - size.width / 2
            y = icon.maxY + iconGap
        case .left:
            x = icon.maxX + iconGap
            y = icon.midY - size.height / 2
        case .right:
            x = icon.minX - iconGap - size.width
            y = icon.midY - size.height / 2
        }

        let screen = NSScreen.screens.first { $0.frame.intersects(icon) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
            y = min(max(y, v.minY + 8), v.maxY - size.height - 8)
        }
        return CGPoint(x: x, y: y)
    }

    /// Rounded-rect body plus a triangular notch pointing at the icon.
    private static func maskImage(size: NSSize, bodyOrigin: CGPoint, bodySize: NSSize,
                                  orientation: DockOrientation,
                                  iconCenterX: CGFloat, iconCenterY: CGFloat,
                                  notch: CGFloat) -> NSImage {
        let radius: CGFloat = 14
        return NSImage(size: size, flipped: false) { _ in
            let body = NSRect(origin: bodyOrigin, size: bodySize)
            let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

            let tri = NSBezierPath()
            switch orientation {
            case .bottom:
                let cx = min(max(iconCenterX, body.minX + radius + notch), body.maxX - radius - notch)
                tri.move(to: NSPoint(x: cx - notch, y: body.minY))
                tri.line(to: NSPoint(x: cx + notch, y: body.minY))
                tri.line(to: NSPoint(x: cx, y: body.minY - notch))
            case .left:
                let cy = min(max(iconCenterY, body.minY + radius + notch), body.maxY - radius - notch)
                tri.move(to: NSPoint(x: body.minX, y: cy - notch))
                tri.line(to: NSPoint(x: body.minX, y: cy + notch))
                tri.line(to: NSPoint(x: body.minX - notch, y: cy))
            case .right:
                let cy = min(max(iconCenterY, body.minY + radius + notch), body.maxY - radius - notch)
                tri.move(to: NSPoint(x: body.maxX, y: cy - notch))
                tri.line(to: NSPoint(x: body.maxX, y: cy + notch))
                tri.line(to: NSPoint(x: body.maxX + notch, y: cy))
            }
            tri.close()

            NSColor.black.setFill()
            path.fill()
            tri.fill()
            return true
        }
    }

    // MARK: Esc to dismiss

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    self?.hide()
                    self?.onDismiss?()
                }
            }
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    // MARK: Click-to-raise

    private func raise(_ thumb: WindowThumbnail) {
        hide()
        onDismiss?()
        guard let (axWindows, matched) = resolveAXWindow(for: thumb),
              let ownerPID = (CGWindowListCopyWindowInfo([.optionIncludingWindow], thumb.id) as? [[String: Any]])?.first?[kCGWindowOwnerPID as String] as? pid_t else { return }

        NSRunningApplication(processIdentifier: ownerPID)?.activate(options: [.activateAllWindows])

        if let matched = matched {
            AXUIElementPerformAction(matched, kAXRaiseAction as CFString)
        } else if let first = axWindows.first {
            AXUIElementPerformAction(first, kAXRaiseAction as CFString)
        }
    }

    // MARK: System Actions (Close / Minimize)

    private func performWindowAction(thumb: WindowThumbnail, actionAttribute: CFString) {
        hide()
        onDismiss?()

        // Only act on a uniquely identified matched window, never fallback to first for destructive actions.
        guard let (_, matched) = resolveAXWindow(for: thumb), let axWindow = matched else { return }

        var buttonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, actionAttribute, &buttonRef) == .success,
           let buttonVal = buttonRef, CFGetTypeID(buttonVal) == AXUIElementGetTypeID() {
            let button = buttonVal as! AXUIElement
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    // MARK: AX Helper

    private func resolveAXWindow(for thumb: WindowThumbnail) -> (axWindows: [AXUIElement], matched: AXUIElement?)? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], thumb.id) as? [[String: Any]])?.first,
              let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }

        let appElement = AXUIElementCreateApplication(ownerPID)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return nil }

        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            if let axTitle = titleRef as? String, axTitle == thumb.title {
                return (axWindows, axWindow)
            }
        }
        return (axWindows, nil)
    }
}

/// Non-activating panel that never becomes key/main, so it never steals focus.
final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Root view that reports cursor enter/exit via a tracking area.
final class TrackingView: NSView {
    var onCursor: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onCursor?(true) }
    override func mouseExited(with event: NSEvent) { onCursor?(false) }
}

/// An image view that reports left clicks.
final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - SwiftUI Views

struct ThumbsView: View {
    let hover: DockItemHover
    let thumbs: [WindowThumbnail]
    let cardW: CGFloat
    let thumbHeight: CGFloat
    let onRaise: (WindowThumbnail) -> Void
    let onClose: (WindowThumbnail) -> Void
    let onMinimize: (WindowThumbnail) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Header
            Text(thumbs.count == 1 ? hover.title : "\(hover.title)  ·  \(thumbs.count) windows")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            // Cards Row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(thumbs, id: \.id) { thumb in
                        ThumbCard(
                            thumb: thumb,
                            appName: hover.title,
                            width: cardW,
                            thumbHeight: thumbHeight,
                            onRaise: { onRaise(thumb) },
                            onClose: { onClose(thumb) },
                            onMinimize: { onMinimize(thumb) }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 12)
        }
    }
}

struct ThumbCard: View {
    let thumb: WindowThumbnail
    let appName: String
    let width: CGFloat
    let thumbHeight: CGFloat
    let onRaise: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(nsImage: thumb.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )

                if isHovered {
                    // Glassy overlay with action buttons
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Material.ultraThin)
                        .frame(width: width, height: thumbHeight)

                    HStack(spacing: 16) {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: onMinimize) {
                            Image(systemName: "minus.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                onRaise()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(thumb.title), window of \(appName). Click to bring to front.")
            .accessibilityAction(named: "Close") { onClose() }
            .accessibilityAction(named: "Minimize") { onMinimize() }

            Text(thumb.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: width, alignment: .center)
        }
        .frame(width: width)
    }
}
