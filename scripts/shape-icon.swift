// Shapes full-bleed square art into a classic macOS icon: an 824x824 rounded
// rect (corner radius 185) centered on a transparent 1024x1024 canvas, with a
// soft drop shadow.
// Usage: swift scripts/shape-icon.swift <input> <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("usage: shape-icon.swift <input> <output.png>\n".data(using: .utf8)!)
    exit(1)
}

let canvas: CGFloat = 1024
let side: CGFloat = 824
let radius: CGFloat = 185
let rect = CGRect(x: (canvas - side) / 2, y: (canvas - side) / 2 + 10, width: side, height: side)

guard let ctx = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(art, in: rect)
ctx.restoreGState()

ctx.addPath(shape)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
ctx.setLineWidth(2)
ctx.strokePath()

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
