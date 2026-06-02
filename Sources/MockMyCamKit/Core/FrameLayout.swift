import Foundation

/// Byte layout of the shared-memory frame buffer that the injected
/// `VirtualCamera.dylib` reads from `/tmp/SimCam.bgra`.
///
/// Header (24 bytes, little-endian uint32 fields):
///   [0..<4]   sequence     — frame counter; 0 means "empty", reader ignores it
///   [4..<8]   timestampMs
///   [8..<12]  width
///   [12..<16] height
///   [16..<20] flags        — see `Flags`
///   [20..<24] reserved
///   [24..]    BGRA pixels, tightly packed (stride = width*4),
///             premultiplied-first, byteOrder32Little
///
/// The reader rejects width/height of 0 or > `maxCanvas`. This must stay
/// byte-for-byte in sync with `SimCamSharedFrameReader.m` in ThirdParty.
public enum FrameLayout {
    public static let headerSize = 24
    public static let maxCanvas = 1280
    public static let bytesPerPixel = 4
    public static let maxPixelBytes = maxCanvas * maxCanvas * bytesPerPixel
    /// 24 + 1280*1280*4 = 6,553,624 — the exact mmap size both sides use.
    public static let totalByteCount = headerSize + maxPixelBytes

    public static let offsetSequence = 0
    public static let offsetTimestampMs = 4
    public static let offsetWidth = 8
    public static let offsetHeight = 12
    public static let offsetFlags = 16
    public static let offsetReserved = 20

    /// Per-frame display preferences carried in the header `flags` field.
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        /// Aspect-fill instead of the default aspect-fit (letterbox).
        public static let fillGravity = Flags(rawValue: 1 << 0)
        /// Mirror horizontally (front-camera "selfie" feel).
        public static let mirror = Flags(rawValue: 1 << 1)
    }
}
