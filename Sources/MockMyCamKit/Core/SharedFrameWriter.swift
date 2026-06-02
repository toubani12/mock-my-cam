import Foundation

public enum SharedFrameWriterError: Error, Equatable {
    case openFailed(errno: Int32)
    case truncateFailed(errno: Int32)
    case mmapFailed(errno: Int32)
    case invalidDimensions(width: Int, height: Int)
    case pixelCountMismatch(expected: Int, got: Int)
}

/// Writes BGRA frames into the mmap'd shared buffer that the injected
/// `VirtualCamera.dylib` reads. The file (`/tmp/SimCam.bgra` by default) maps to
/// `/private/tmp` on the host, which the simulator sees as `/tmp` — that shared
/// inode is the whole transport.
///
/// Commit protocol (matches the reader's expectations): write the pixels first,
/// then the header fields, and write `sequence` **last** — the reader treats a
/// changed sequence as "a complete new frame is ready". Finally `msync` to flush.
public final class SharedFrameWriter {
    public static let defaultPath = "/tmp/SimCam.bgra"

    private let fd: Int32
    private let base: UnsafeMutableRawPointer
    private let lock = NSLock()
    private var sequence: UInt32 = 0
    private let startTime = Date()

    public init(path: String = SharedFrameWriter.defaultPath) throws {
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { throw SharedFrameWriterError.openFailed(errno: errno) }

        if ftruncate(fd, off_t(FrameLayout.totalByteCount)) != 0 {
            let e = errno
            close(fd)
            throw SharedFrameWriterError.truncateFailed(errno: e)
        }

        guard let map = mmap(nil, FrameLayout.totalByteCount,
                             PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              map != MAP_FAILED else {
            let e = errno
            close(fd)
            throw SharedFrameWriterError.mmapFailed(errno: e)
        }

        self.fd = fd
        self.base = map
    }

    deinit {
        munmap(base, FrameLayout.totalByteCount)
        close(fd)
    }

    /// Publishes one frame. `bgra` must be tightly packed (count == width*height*4).
    /// Returns the published sequence number.
    @discardableResult
    public func write(bgra: Data, width: Int, height: Int,
                      flags: FrameLayout.Flags = []) throws -> UInt32 {
        guard width > 0, height > 0,
              width <= FrameLayout.maxCanvas, height <= FrameLayout.maxCanvas else {
            throw SharedFrameWriterError.invalidDimensions(width: width, height: height)
        }
        let expected = width * height * FrameLayout.bytesPerPixel
        guard bgra.count == expected else {
            throw SharedFrameWriterError.pixelCountMismatch(expected: expected, got: bgra.count)
        }

        lock.lock()
        defer { lock.unlock() }

        // 1) Pixels first.
        _ = bgra.withUnsafeBytes { src in
            memcpy(base + FrameLayout.headerSize, src.baseAddress!, expected)
        }

        // 2) Header fields (everything except the sequence "commit").
        let ms = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince(startTime) * 1000))
        store(UInt32(width), at: FrameLayout.offsetWidth)
        store(UInt32(height), at: FrameLayout.offsetHeight)
        store(flags.rawValue, at: FrameLayout.offsetFlags)
        store(ms, at: FrameLayout.offsetTimestampMs)
        store(0, at: FrameLayout.offsetReserved)

        // 3) Sequence last = commit. Never publish 0 (reader treats it as empty).
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        store(sequence, at: FrameLayout.offsetSequence)

        // 4) Flush header + pixels to the backing file so the reader sees them.
        msync(base, FrameLayout.headerSize + expected, MS_SYNC)
        return sequence
    }

    private func store(_ value: UInt32, at offset: Int) {
        var le = value.littleEndian
        memcpy(base + offset, &le, 4)
    }
}
