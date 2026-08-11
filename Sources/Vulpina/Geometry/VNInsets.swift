/// Edge insets that describe padding on each side of a rectangle, in points.
public struct VNInsets: Sendable, Hashable, Codable {
    /// Inset from the top edge.
    public var top: Double
    /// Inset from the left edge.
    public var left: Double
    /// Inset from the bottom edge.
    public var bottom: Double
    /// Inset from the right edge.
    public var right: Double

    /// Creates insets with the given values.
    @inlinable public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }

    /// Zero insets on all sides.
    public static let zero = VNInsets(top: 0, left: 0, bottom: 0, right: 0)

    /// Creates uniform insets (same value on every side).
    @inlinable public init(_ value: Double) {
        self.init(top: value, left: value, bottom: value, right: value)
    }
}

extension VNInsets: CustomStringConvertible {
    public var description: String { "{top:\(top), left:\(left), bottom:\(bottom), right:\(right)}" }
}
