// Draws Stint's app icon without Xcode: Resources/AppIcon.icns, plus docs/brand/stint-logo-1024.png
// (the square logo for Teamwork's Developer Portal and directory listing).
// Run from the repo root: SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift Resources/make-icon.swift
//
// The mark: a timer ring on slate, three quarters run, lilac fading up to white, with the pink live dot
// (Brand.pink, the app's LiveDot) as its running end. No letterform: Teamwork's own symbol is a "t" with
// a pink dot, and Stint is independent of Teamwork.
import AppKit
import SwiftUI

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let a = a.components!, b = b.components!
    return CGColor(srgbRed: a[0] + (b[0] - a[0]) * t, green: a[1] + (b[1] - a[1]) * t, blue: a[2] + (b[2] - a[2]) * t, alpha: 1)
}
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let top = rgb(0x2E2B5C), bottom = rgb(0x16152C) // slate #1D1C39, lit from above
let lilac = rgb(0x9C82F5), white = rgb(0xFFFFFF), pink = rgb(0xFF22B1) // Brand.purple (Dark Mode), Brand.pink

/// The ring, in the 824-pt icon body (y down). `boost` thickens it at 16 and 32 px so it stays legible.
func drawRing(_ ctx: CGContext, boost: CGFloat) {
    let c = CGPoint(x: 412, y: 412), r: CGFloat = 236, w = 92 * boost
    let start = -CGFloat.pi / 2, end = CGFloat.pi // 12 o'clock, clockwise to 9 o'clock
    ctx.setLineWidth(w)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.12))
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.strokePath()
    let n = 120 // Core Graphics has no public conic gradient: short overlapping segments instead
    for i in 0..<n {
        let t = CGFloat(i) / CGFloat(n)
        ctx.setStrokeColor(mix(lilac, white, min(1, t * 1.6)))
        ctx.setLineCap(i == 0 ? .round : .butt)
        ctx.addArc(center: c, radius: r, startAngle: start + (end - start) * t,
                   endAngle: min(end, start + (end - start) * (t + 1.5 / CGFloat(n))), clockwise: false)
        ctx.strokePath()
    }
    let head = CGPoint(x: c.x + r * cos(end), y: c.y + r * sin(end))
    for (d, color) in [(w + 28 * boost, mix(top, bottom, 0.5)), (w, pink)] { // pink dot, cut out of the ring
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: head.x - d / 2, y: head.y - d / 2, width: d, height: d))
    }
}

/// fullBleed: the square logo, without the mask, margin or shadow; the ring keeps its place in the body.
func render(px: Int, fullBleed: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: (fullBleed ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)! // logo: opaque
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: s, y: -s) // 1024-pt canvas, y down
    // macOS icon grid (Big Sur through 26): an 824-pt continuous-corner squircle centred on the canvas.
    let body = fullBleed ? CGRect(x: 0, y: 0, width: 1024, height: 1024) : CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = fullBleed ? CGPath(rect: body, transform: nil)
        : RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: body).cgPath
    let fill = CGGradient(colorsSpace: srgb, colors: [top, bottom] as CFArray, locations: nil)!
    if !fullBleed { // shadow offsets ignore the CTM, so they're in pixels
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 20 * s, color: rgb(0, 0.3))
        ctx.addPath(shape); ctx.setFillColor(bottom); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
    ctx.saveGState()
    ctx.translateBy(x: body.minX, y: body.minY); ctx.scaleBy(x: body.width / 824, y: body.width / 824)
    drawRing(ctx, boost: px <= 16 ? 1.45 : px <= 32 ? 1.2 : 1)
    ctx.restoreGState()
    if !fullBleed && px >= 64 { // glass rim: a thin light edge, brightest at the top
        let rim = CGGradient(colorsSpace: srgb, colors: [rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0.05)] as CFArray, locations: nil)!
        ctx.addPath(shape); ctx.setLineWidth(6); ctx.replacePathWithStrokedPath(); ctx.clip()
        ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "couldn't write \(path)")
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset").path
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    writePNG(render(px: pt), "\(iconset)/icon_\(pt)x\(pt).png")
    writePNG(render(px: pt * 2), "\(iconset)/icon_\(pt)x\(pt)@2x.png")
}
let iconutil = try Process.run(URL(fileURLWithPath: "/usr/bin/iconutil"), arguments: ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"])
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
try FileManager.default.createDirectory(atPath: "docs/brand", withIntermediateDirectories: true)
writePNG(render(px: 1024, fullBleed: true), "docs/brand/stint-logo-1024.png")
print("Resources/AppIcon.icns, docs/brand/stint-logo-1024.png")
