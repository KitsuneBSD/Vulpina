/// A width and height, measured in points (not pixels).
public struct VNSize: Sendable, Hashable, Codable {
    /// Horizontal extent, in points. Must be ≥ 0 in well-formed usage.
    public var width: Double
    /// Vertical extent, in points. Must be ≥ 0 in well-formed usage.
    public var height: Double

    /// Creates a size with the given `width` and `height`.
    @inlinable public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The zero size (0 × 0).
    public static let zero = VNSize(width: 0, height: 0)

    /// Returns `true` when both dimensions are zero.
    @inlinable public var isEmpty: Bool { width == 0 && height == 0 }
}

extension VNSize: CustomStringConvertible {
    public var description: String { "\(width)×\(height)" }
}
