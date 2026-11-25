// Renders the Pilothouse app icon (1024×1024 master + all macOS sizes).
// Usage: swift Scripts/make-icon.swift <output .appiconset directory>
import AppKit
import CoreGraphics

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func roundedTriangle(center c: CGPoint, size: CGFloat, corner: CGFloat) -> CGPath {
    // Equilateral-ish play triangle pointing right, optically centered.
    let h = size, w = size * 0.92
    let p1 = CGPoint(x: c.x - w * 0.40, y: c.y + h / 2)
    let p2 = CGPoint(x: c.x - w * 0.40, y: c.y - h / 2)
    let p3 = CGPoint(x: c.x + w * 0.60, y: c.y)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2))
    path.addArc(tangent1End: p2, tangent2End: p3, radius: corner)
    path.addArc(tangent1End: p3, tangent2End: p1, radius: corner)
    path.addArc(tangent1End: p1, tangent2End: p2, radius: corner)
    path.closeSubpath()
    return path
}

let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

// macOS icon grid: 824pt body, centered, with soft shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(body, 186)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x2A1B6E)); ctx.fillPath()
ctx.restoreGState()

// Background gradient: violet → magenta → coral.
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [color(0x4B2FE8), color(0xA13BD8), color(0xFF5E7A), color(0xFF9A4D)] as CFArray,
                    locations: [0, 0.45, 0.82, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
// Soft top glow
let glow = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 860), startRadius: 0, endCenter: CGPoint(x: 380, y: 860), endRadius: 560, options: [])
ctx.restoreGState()

// Frosted "screen" panel (Liquid Glass feel).
let screen = CGRect(x: 222, y: 262, width: 580, height: 500)
let screenPath = squircle(screen, 112)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x1A0B4A, 0.35))
ctx.addPath(screenPath); ctx.setFillColor(color(0xFFFFFF, 0.18)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(screenPath); ctx.clip()
let sheen = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.30), color(0xFFFFFF, 0.04)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: screen.maxY), end: CGPoint(x: 0, y: screen.minY), options: [])
// Arcade scanlines
ctx.setFillColor(color(0xFFFFFF, 0.07))
var y = screen.minY + 18
while y < screen.maxY { ctx.fill(CGRect(x: screen.minX, y: y, width: screen.width, height: 7)); y += 26 }
ctx.restoreGState()
ctx.addPath(screenPath); ctx.setStrokeColor(color(0xFFFFFF, 0.55)); ctx.setLineWidth(6); ctx.strokePath()

// Play glyph
let tri = roundedTriangle(center: CGPoint(x: 522, y: 512), size: 250, corner: 34)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x3A0E6B, 0.45))
ctx.addPath(tri); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()

// Small "download" pill under the screen
let pill = CGRect(x: 432, y: 176, width: 160, height: 44)
ctx.addPath(squircle(pill, 22)); ctx.setFillColor(color(0xFFFFFF, 0.9)); ctx.fillPath()
ctx.setFillColor(color(0xFF5E7A))
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 512, y: 184)); arrow.addLine(to: CGPoint(x: 492, y: 206)); arrow.addLine(to: CGPoint(x: 532, y: 206)); arrow.closeSubpath()
ctx.addPath(arrow); ctx.fillPath()
ctx.fill(CGRect(x: 504, y: 205, width: 16, height: 10))

// Glass rim
ctx.addPath(squircle(body.insetBy(dx: 3, dy: 3), 183)); ctx.setStrokeColor(color(0xFFFFFF, 0.22)); ctx.setLineWidth(6); ctx.strokePath()

let master = ctx.makeImage()!
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func write(_ px: Int, _ name: String) {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appending(path: name))
}

var images: [String] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        write(base * scale, name)
        images.append(#"{ "idiom" : "mac", "size" : "\#(base)x\#(base)", "scale" : "\#(scale)x", "filename" : "\#(name)" }"#)
    }
}
let json = "{ \"images\" : [\n  " + images.joined(separator: ",\n  ") + "\n], \"info\" : { \"author\" : \"xcode\", \"version\" : 1 } }\n"
try! json.write(to: outDir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
write(1024, "../../../Assets/icon-1024.png")
print("ok")
