// Draws the icon layers into Resources/Snap.icon/Assets.
// Run from the project root:  swift tools/make-icon.swift
import AppKit

let size = 1024
let out = URL(fileURLWithPath: "Resources/Snap.icon/Assets", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func layer(_ name: String, draw: (CGContext) -> Void) throws {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: "\(name).png"))
}

// Viewfinder corners.
try layer("corners") { ctx in
    let lo: CGFloat = 236, hi: CGFloat = 788, arm: CGFloat = 156
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(60)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (x, y, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] {
        ctx.move(to: CGPoint(x: x, y: y + dy * arm))
        ctx.addLine(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + dx * arm, y: y))
    }
    ctx.strokePath()
}

// The selected area.
try layer("selection") { ctx in
    let rect = CGRect(x: 360, y: 392, width: 304, height: 240)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil))
    ctx.setFillColor(CGColor(red: 0.22, green: 0.56, blue: 1, alpha: 1))
    ctx.fillPath()
}

print("Wrote layers to \(out.path)")
