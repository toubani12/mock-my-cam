import Foundation

/// Connects the active `FrameProvider` to the `SharedFrameWriter`: every frame
/// the provider emits is published into the shared buffer with the current
/// display flags. Switching source stops the old provider and starts the new.
public final class FramePipeline {
    private let writer: SharedFrameWriter
    private let lock = NSLock()
    private var provider: FrameProvider?
    private var _flags = FrameLayout.Flags()

    /// Display preferences (mirror / fill) applied to every published frame.
    public var flags: FrameLayout.Flags {
        get { lock.lock(); defer { lock.unlock() }; return _flags }
        set { lock.lock(); _flags = newValue; lock.unlock() }
    }

    /// Optional hook for a live preview of what's being sent (called per frame).
    public var onFramePublished: ((BGRAFrame) -> Void)?

    public init(path: String = SharedFrameWriter.defaultPath) throws {
        writer = try SharedFrameWriter(path: path)
    }

    /// Switches to a new frame source.
    public func use(_ newProvider: FrameProvider) {
        stop()
        lock.lock(); provider = newProvider; lock.unlock()
        newProvider.start { [weak self] frame in self?.publish(frame) }
    }

    public func stop() {
        lock.lock(); let p = provider; provider = nil; lock.unlock()
        p?.stop()
    }

    private func publish(_ frame: BGRAFrame) {
        _ = try? writer.write(bgra: frame.data, width: frame.width, height: frame.height, flags: flags)
        onFramePublished?(frame)
    }
}
