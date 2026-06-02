import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

enum TestSupportError: Error { case contextCreation, pngWrite }

/// A solid-color CGImage (sRGB, opaque).
func solidCGImage(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) throws -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw TestSupportError.contextCreation
    }
    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let img = ctx.makeImage() else { throw TestSupportError.contextCreation }
    return img
}

/// A CGImage split horizontally: `top` color in the top half, `bottom` in the
/// bottom half. (CG origin is bottom-left, so the top color is filled at high y;
/// `makeImage()` produces an upright CGImage whose top row is the `top` color.)
func halfSplitCGImage(width: Int, height: Int,
                      top: (CGFloat, CGFloat, CGFloat),
                      bottom: (CGFloat, CGFloat, CGFloat)) throws -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw TestSupportError.contextCreation
    }
    ctx.setFillColor(red: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
    ctx.setFillColor(red: top.0, green: top.1, blue: top.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
    guard let img = ctx.makeImage() else { throw TestSupportError.contextCreation }
    return img
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TestSupportError.pngWrite
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw TestSupportError.pngWrite }
}

/// Samples a screenshot's pixel at fractional (fx, fy) — (0,0) top-left.
func sampleColor(_ rep: NSBitmapImageRep, fx: Double, fy: Double) -> (r: Double, g: Double, b: Double) {
    let x = min(rep.pixelsWide - 1, max(0, Int(Double(rep.pixelsWide) * fx)))
    let y = min(rep.pixelsHigh - 1, max(0, Int(Double(rep.pixelsHigh) * fy)))
    let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    return (Double(c?.redComponent ?? 0), Double(c?.greenComponent ?? 0), Double(c?.blueComponent ?? 0))
}
