/// A premultiplied RGBA8 pixel buffer in top-left / y-down screen coordinates.
///
/// Each pixel occupies 4 consecutive bytes: [R, G, B, A] (premultiplied).
/// Row 0 is the topmost row on screen.
public struct VNFramebuffer: Sendable {
    public let widthPixels: Int
    public let heightPixels: Int
    /// Raw pixel bytes: `[R, G, B, A]` per pixel, row-major, y-down.
    public var bytes: [UInt8]

    public init(widthPixels: Int, heightPixels: Int) {
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.bytes = [UInt8](repeating: 0, count: widthPixels * heightPixels * 4)
    }

    @inlinable public func byteOffset(x: Int, y: Int) -> Int {
        (y * widthPixels + x) * 4
    }

    @inlinable public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = byteOffset(x: x, y: y)
        return (bytes[i], bytes[i+1], bytes[i+2], bytes[i+3])
    }

    @inlinable public mutating func setPixel(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = byteOffset(x: x, y: y)
        bytes[i] = r; bytes[i+1] = g; bytes[i+2] = b; bytes[i+3] = a
    }

    /// Fills the entire buffer with zeros (transparent black).
    public mutating func clear() {
        bytes = [UInt8](repeating: 0, count: bytes.count)
    }
}
