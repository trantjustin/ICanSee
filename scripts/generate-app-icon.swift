#!/usr/bin/env swift
// Generates a 1024x1024 AppIcon PNG for "I Can See!".
// Layout mirrors the other IAm/ICan apps: gradient background, motif in the
// upper-right corner (lotus on IAmMindful), centered stacked wordmark.
// Here the motif is a color-wheel + reticle (the in-app crosshair).
// Usage: swift scripts/generate-app-icon.swift <output.png>

import AppKit

_ = NSApplication.shared

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-app-icon.swift <output.png>\n".utf8))
    exit(1)
}

let outPath = CommandLine.arguments[1]
let side: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side),
    pixelsHigh: Int(side),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else { fatalError("failed to create bitmap rep") }
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsCtx
let ctx = nsCtx.cgContext

// 1. Rainbow background gradient — the app is about color, so the icon
//    should radiate color. Slightly desaturated so the white wordmark
//    still reads cleanly on every band.
let bgColors: [CGColor] = [
    NSColor(red: 0.88, green: 0.22, blue: 0.30, alpha: 1).cgColor, // red
    NSColor(red: 0.98, green: 0.55, blue: 0.18, alpha: 1).cgColor, // orange
    NSColor(red: 0.95, green: 0.82, blue: 0.22, alpha: 1).cgColor, // yellow
    NSColor(red: 0.32, green: 0.72, blue: 0.36, alpha: 1).cgColor, // green
    NSColor(red: 0.22, green: 0.45, blue: 0.88, alpha: 1).cgColor, // blue
    NSColor(red: 0.55, green: 0.25, blue: 0.78, alpha: 1).cgColor  // purple
]
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: bgColors as CFArray,
                    locations: [0.0, 0.20, 0.40, 0.60, 0.80, 1.0])!
ctx.drawLinearGradient(bg,
                       start: CGPoint(x: 0, y: side),
                       end: CGPoint(x: side, y: 0),
                       options: [])

// 2. Soft radial highlight upper-left for depth.
let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.25).cgColor,
                                    NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray,
                           locations: [0, 1])!
ctx.drawRadialGradient(highlight,
                       startCenter: CGPoint(x: side * 0.25, y: side * 0.82),
                       startRadius: 0,
                       endCenter: CGPoint(x: side * 0.25, y: side * 0.82),
                       endRadius: side * 0.65,
                       options: [])

// 3. Color-wheel + reticle motif in the bottom-right corner.
//    AppIcon coordinate origin is bottom-left in AppKit, so a small y value
//    puts the motif near the *bottom* of the icon — matching the user's request.
do {
    ctx.saveGState()
    let cx = side * 0.74
    let cy = side * 0.16
    ctx.translateBy(x: cx, y: cy)

    // Color-wheel ring: 6 rainbow wedges.
    let outerR: CGFloat = 110
    let innerR: CGFloat = 58
    let wedgeColors: [NSColor] = [
        NSColor(red: 0.92, green: 0.20, blue: 0.22, alpha: 1), // red
        NSColor(red: 1.00, green: 0.60, blue: 0.12, alpha: 1), // orange
        NSColor(red: 1.00, green: 0.92, blue: 0.22, alpha: 1), // yellow
        NSColor(red: 0.28, green: 0.80, blue: 0.32, alpha: 1), // green
        NSColor(red: 0.22, green: 0.48, blue: 0.96, alpha: 1), // blue
        NSColor(red: 0.66, green: 0.28, blue: 0.88, alpha: 1)  // purple
    ]
    let wedgeAngle = (2 * CGFloat.pi) / CGFloat(wedgeColors.count)
    for (i, color) in wedgeColors.enumerated() {
        let start = CGFloat(i) * wedgeAngle - .pi / 2
        let end = start + wedgeAngle
        ctx.setFillColor(color.cgColor)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addArc(center: .zero, radius: outerR, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }

    // Punch out the inner hole so the wheel reads as a ring.
    ctx.setBlendMode(.destinationOut)
    ctx.fillEllipse(in: CGRect(x: -innerR, y: -innerR, width: innerR * 2, height: innerR * 2))
    ctx.setBlendMode(.normal)

    // White reticle on top — the same crosshair the user sees in-app.
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(8)
    let reticleR = innerR + 20
    ctx.strokeEllipse(in: CGRect(x: -reticleR, y: -reticleR, width: reticleR * 2, height: reticleR * 2))
    let tick: CGFloat = 42
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: -tick, y: 0)); ctx.addLine(to: CGPoint(x: tick, y: 0))
    ctx.move(to: CGPoint(x: 0, y: -tick)); ctx.addLine(to: CGPoint(x: 0, y: tick))
    ctx.strokePath()

    ctx.restoreGState()
}

// 4. "I CAN / SEE!" stacked, bold rounded, white — same treatment as IAmMindful.
let text = "I CAN\nSEE!" as NSString
let font = NSFont.systemFont(ofSize: 200, weight: .black).withRoundedDesign()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 20
shadow.shadowOffset = NSSize(width: 0, height: -6)

let style = NSMutableParagraphStyle()
style.alignment = .center
style.lineBreakMode = .byClipping
style.lineHeightMultiple = 0.92

let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .kern: -10,
    .shadow: shadow,
    .paragraphStyle: style
]
let attrStr = NSAttributedString(string: text as String, attributes: attrs)
let textBounds = attrStr.boundingRect(
    with: NSSize(width: side, height: side),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
let rect = NSRect(x: 0,
                  y: (side - textBounds.height) / 2,
                  width: side,
                  height: textBounds.height)
text.draw(in: rect, withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()

// Re-render to opaque (App Store rejects alpha).
guard let sourceCGImage = rep.cgImage else { fatalError("no CGImage") }
guard let opaqueCtx = CGContext(
    data: nil,
    width: Int(side), height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("failed to create opaque context") }
opaqueCtx.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: side, height: side))
guard let opaqueImage = opaqueCtx.makeImage() else { fatalError("makeImage failed") }
let finalRep = NSBitmapImageRep(cgImage: opaqueImage)

guard let png = finalRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}

try! png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) (\(png.count / 1024) KB)")

extension NSFont {
    func withRoundedDesign() -> NSFont {
        let desc = fontDescriptor.withDesign(.rounded) ?? fontDescriptor
        return NSFont(descriptor: desc, size: pointSize) ?? self
    }
}
