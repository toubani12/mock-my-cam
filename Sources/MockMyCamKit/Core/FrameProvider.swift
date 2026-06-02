import Foundation

/// One tightly-packed BGRA frame ready for `SharedFrameWriter`
/// (count == width*height*4, stride == width*4, row 0 == top).
public struct BGRAFrame: Sendable, Equatable {
    public let data: Data
    public let width: Int
    public let height: Int
    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

/// A source of BGRA frames (Mac webcam, image, video). `start` begins delivering
/// frames to the callback (on an arbitrary queue); `stop` ends delivery.
public protocol FrameProvider: AnyObject {
    func start(_ onFrame: @escaping (BGRAFrame) -> Void)
    func stop()
}
