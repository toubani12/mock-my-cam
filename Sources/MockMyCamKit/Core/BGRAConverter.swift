import Foundation
import CoreGraphics
import CoreVideo
import CoreImage

/// Converts images / pixel buffers into tightly-packed BGRA frames that match
/// what the injected reader expects: `byteOrder32Little | premultipliedFirst`
/// (i.e. B,G,R,A in memory), stride == width*4, row 0 == top, scaled to fit
/// within `maxDimension` while preserving aspect.
public enum BGRAConverter {
    /// BGRA bitmap format, identical to `SimCamSharedFrameReader.m`.
    static let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
        | CGImageAlphaInfo.premultipliedFirst.rawValue

    /// Downscale-only fit: both dimensions <= `maxDimension`, aspect preserved.
    public static func fittedSize(width: Int, height: Int,
                                  maxDimension: Int = FrameLayout.maxCanvas) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (1, 1) }
        let scale = min(1.0, Double(maxDimension) / Double(max(width, height)))
        return (max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded())))
    }

    public static func frame(from cgImage: CGImage,
                             maxDimension: Int = FrameLayout.maxCanvas) -> BGRAFrame? {
        let (w, h) = fittedSize(width: cgImage.width, height: cgImage.height, maxDimension: maxDimension)
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let ok = buffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else { return false }
            // No CTM flip: a raw bitmap context already lays out memory row 0 as
            // the top scanline, which is exactly how the reader interprets the
            // buffer (verified end-to-end by E2EInjectionTests.testImageOrientation).
            // This also matches the CVPixelBuffer fast path (row 0 -> row 0).
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        return BGRAFrame(data: Data(buffer), width: w, height: h)
    }

    public static func frame(from pixelBuffer: CVPixelBuffer,
                             maxDimension: Int = FrameLayout.maxCanvas) -> BGRAFrame? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        // Fast path: already BGRA and within size — strip any row padding.
        if format == kCVPixelFormatType_32BGRA, w <= maxDimension, h <= maxDimension {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let srcStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let dstStride = w * 4
            var out = [UInt8](repeating: 0, count: dstStride * h)
            out.withUnsafeMutableBytes { dst in
                for row in 0..<h {
                    memcpy(dst.baseAddress!.advanced(by: row * dstStride),
                           base.advanced(by: row * srcStride),
                           dstStride)
                }
            }
            return BGRAFrame(data: Data(out), width: w, height: h)
        }

        // General path (needs scaling or non-BGRA): go via CGImage.
        guard let cg = cgImage(from: pixelBuffer) else { return nil }
        return frame(from: cg, maxDimension: maxDimension)
    }

    /// Reverse direction: a displayable CGImage from a BGRA frame (for the
    /// Mac-side live preview of what's being sent). Matches the reader's format.
    public static func cgImage(from frame: BGRAFrame) -> CGImage? {
        guard let provider = CGDataProvider(data: frame.data as CFData) else { return nil }
        return CGImage(width: frame.width, height: frame.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ci, from: ci.extent)
    }
}
