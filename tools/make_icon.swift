#!/usr/bin/env swift
// Renders DockPeek's app icon into Resources/AppIcon.icns.
// Motif: a preview window "popping" up out of a Dock icon, on a blue gradient tile.
// Run:  swift tools/make_icon.swift
import AppKit

func draw(size S: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Background tile (rounded square with gradient).
    let inset = S * 0.085
    let tile = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: S * 0.225, yRadius: S * 0.225)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.56, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.92, alpha: 1),
    ])!
    gradient.draw(in: tilePath, angle: -90)

    // Dock icon chip near the bottom.
    let chipW = S * 0.20
    let chip = NSRect(x: (S - chipW) / 2, y: S * 0.20, width: chipW, height: chipW)
    let chipPath = NSBezierPath(roundedRect: chip, xRadius: chipW * 0.24, yRadius: chipW * 0.24)
    NSColor(calibratedWhite: 1, alpha: 0.32).setFill()
    chipPath.fill()

    // Preview window floating above, with a downward notch pointing at the chip.
    let winW = S * 0.52, winH = S * 0.34
    let win = NSRect(x: (S - winW) / 2, y: S * 0.42, width: winW, height: winH)
    let winPath = NSBezierPath(roundedRect: win, xRadius: S * 0.05, yRadius: S * 0.05)
    let notch = S * 0.045
    let cx = win.midX
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: cx - notch, y: win.minY + 1))
    tri.line(to: NSPoint(x: cx + notch, y: win.minY + 1))
    tri.line(to: NSPoint(x: cx, y: win.minY - notch))
    tri.close()
    NSColor.white.setFill()
    winPath.fill()
    tri.fill()

    // Title bar accent + traffic-light dot on the preview window.
    let bar = NSRect(x: win.minX, y: win.maxY - winH * 0.26, width: winW, height: winH * 0.26)
    let barPath = NSBezierPath(roundedRect: bar, xRadius: S * 0.05, yRadius: S * 0.05)
    NSColor(calibratedRed: 0.90, green: 0.93, blue: 1.0, alpha: 1).setFill()
    barPath.fill()
    NSColor(calibratedRed: 0.36, green: 0.56, blue: 0.98, alpha: 1).setFill()
    let dot = NSRect(x: bar.minX + S * 0.045, y: bar.midY - S * 0.018,
                     width: S * 0.036, height: S * 0.036)
    NSBezierPath(ovalIn: dot).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (base point size, scale) → filename
let variants: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (pt, scale) in variants {
    let px = pt * scale
    let rep = draw(size: CGFloat(px))
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    try! png(rep).write(to: iconset.appendingPathComponent(name))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ wrote \(icns.path)" : "✗ iconutil failed")
