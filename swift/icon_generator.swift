#!/usr/bin/env swift
// Generates icon_1024.png — an equalizer-style waveform icon for M4BtoMP3.
// Run with:  swift icon_generator.swift
// Then package with make_icns.sh to produce AppIcon.icns.

import AppKit

let W: CGFloat = 1024
let H: CGFloat = 1024

// ── Offscreen bitmap ──────────────────────────────────────────────────────────

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bitmapFormat: [],
    bytesPerRow: 0, bitsPerPixel: 0
)!

let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gc
let cg = gc.cgContext
let cs = CGColorSpaceCreateDeviceRGB()

// ── Background gradient (deep navy → rich blue, top to bottom) ────────────────
// CG origin is bottom-left, so y=H is the top of the image.

let bgColors: [CGColor] = [
    CGColor(red: 0.05, green: 0.10, blue: 0.22, alpha: 1),   // top — deep navy
    CGColor(red: 0.09, green: 0.21, blue: 0.42, alpha: 1),   // bottom — rich blue
]
let bgGrad = CGGradient(colorsSpace: cs, colors: bgColors as CFArray, locations: [0, 1])!
cg.drawLinearGradient(bgGrad,
    start: CGPoint(x: W / 2, y: H),
    end:   CGPoint(x: W / 2, y: 0),
    options: [])

// ── Radial vignette (subtle dark edges) ───────────────────────────────────────

let vigColors: [CGColor] = [
    CGColor(red: 0, green: 0, blue: 0, alpha: 0),
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.42),
]
let vigGrad = CGGradient(colorsSpace: cs, colors: vigColors as CFArray, locations: [0, 1])!
cg.drawRadialGradient(vigGrad,
    startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: W * 0.28,
    endCenter:   CGPoint(x: W / 2, y: H / 2), endRadius:   W * 0.72,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// ── Equalizer bars ────────────────────────────────────────────────────────────

let heightRatios: [CGFloat] = [0.22, 0.42, 0.64, 0.80, 0.64, 0.42, 0.22]
let barRGB: [(CGFloat, CGFloat, CGFloat)] = [
    (0.33, 0.67, 1.00),   // outer — bright blue
    (0.20, 0.76, 0.97),
    (0.08, 0.84, 0.92),
    (0.00, 0.90, 0.82),   // centre — cyan
    (0.08, 0.84, 0.92),
    (0.20, 0.76, 0.97),
    (0.33, 0.67, 1.00),   // outer — bright blue
]

let numBars   = heightRatios.count
let maxBarH   = H * 0.60
let barW      = CGFloat(84)
let gap       = CGFloat(46)
let totalW    = CGFloat(numBars) * barW + CGFloat(numBars - 1) * gap
let startX    = (W - totalW) / 2
let centerY   = H / 2

for i in 0 ..< numBars {
    let bh     = maxBarH * heightRatios[i]
    let bx     = startX + CGFloat(i) * (barW + gap)
    let by     = centerY - bh / 2
    let (r, g, b) = barRGB[i]
    let radius = barW / 2

    cg.saveGState()

    // Glow
    cg.setShadow(offset: CGSize(width: 0, height: 0),
                 blur: 30,
                 color: CGColor(red: r, green: g, blue: b, alpha: 0.55))

    // Bar (rounded pill)
    cg.addPath(CGPath(roundedRect: CGRect(x: bx, y: by, width: barW, height: bh),
                      cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
    cg.fillPath()

    cg.restoreGState()
}

// ── Write PNG ─────────────────────────────────────────────────────────────────

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to produce PNG\n", stderr); exit(1)
}
let outURL = URL(fileURLWithPath: "icon_1024.png")
do {
    try png.write(to: outURL)
    print("Saved icon_1024.png")
} catch {
    fputs("Write error: \(error)\n", stderr); exit(1)
}
