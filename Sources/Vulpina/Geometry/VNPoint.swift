/// A point in 2D space, measured in points (not pixels).
///
/// Use ``VNPoint`` wherever you need a position. Pixel coordinates are
/// derived at render time by multiplying by the window's `backingScaleFactor`.
public struct VNPoint: Sendable, Hashable, Codable {
    /// Horizontal position, in points. Increases to the right.
    public var x: Double
    /// Vertical position, in points. Increases upward (bottom-left origin).
    public var y: Double

    /// Creates a point at (`x`, `y`).
    @inlinable public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The origin (0, 0).
    public static let zero = VNPoint(x: 0, y: 0)
}

extension VNPoint: CustomStringConvertible {
    public var description: String { "(\(x), \(y))" }
}

extension VNPoint {
    /// Returns a point translated by (`dx`, `dy`).
    @inlinable public func translated(by dx: Double, _ dy: Double) -> VNPoint {
        VNPoint(x: x + dx, y: y + dy)
    }
}
