// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import ApplicationServices

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
        let cardsWidth = CGFloat(count) * cardW + CGFloat(count - 1) * spacing
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

        // Header: app name + window count.
        let header = NSTextField(labelWithString:
            count == 1 ? hover.title : "\(hover.title)  ·  \(count) windows")
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .labelColor
        header.lineBreakMode = .byTruncatingTail
        header.frame = NSRect(x: bodyOrigin.x + padding,
                              y: bodyOrigin.y + bodyHeight - padding - headerHeight,
                              width: bodyWidth - padding * 2, height: headerHeight)
        content.addSubview(header)

        // Cards row.
        var x = bodyOrigin.x + padding
        let rowY = bodyOrigin.y + padding
        for thumb in thumbs {
            let card = makeCard(thumb, appName: hover.title, width: cardW,
                                origin: CGPoint(x: x, y: rowY))
            content.addSubview(card)
            x += cardW + spacing
        }

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

    private func makeCard(_ thumb: WindowThumbnail, appName: String,
                          width: CGFloat, origin: CGPoint) -> NSView {
        let cardH = thumbHeight + 4 + labelHeight
        let card = NSView(frame: NSRect(origin: origin, size: NSSize(width: width, height: cardH)))

        let label = NSTextField(labelWithString: thumb.title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 0, y: 0, width: width, height: labelHeight)
        card.addSubview(label)

        let imageView = ClickableImageView(frame:
            NSRect(x: 0, y: labelHeight + 4, width: width, height: thumbHeight))
        imageView.image = thumb.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        imageView.onClick = { [weak self] in self?.raise(thumb) }

        // VoiceOver.
        imageView.setAccessibilityElement(true)
        imageView.setAccessibilityRole(.button)
        imageView.setAccessibilityLabel("\(thumb.title), window of \(appName). Click to bring to front.")
        card.addSubview(imageView)
        return card
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
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], thumb.id)
                            as? [[String: Any]])?.first,
              let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { return }

        NSRunningApplication(processIdentifier: ownerPID)?.activate(options: [.activateAllWindows])

        let appElement = AXUIElementCreateApplication(ownerPID)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            if let axTitle = titleRef as? String, axTitle == thumb.title {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }
        if let first = axWindows.first {
            AXUIElementPerformAction(first, kAXRaiseAction as CFString)
        }
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
