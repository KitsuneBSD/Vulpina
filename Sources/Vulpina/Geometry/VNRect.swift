/// A rectangle defined by an origin and a size, in points.
///
/// The coordinate system has its origin at the bottom-left (AppKit style,
/// `isFlipped == false`). Negative width or height is allowed for intermediate
/// computations but represents a non-canonical rect; use ``standardized`` to
/// normalise.
public struct VNRect: Sendable, Hashable, Codable {
    /// The bottom-left corner of the rectangle.
    public var origin: VNPoint
    /// The extent of the rectangle.
    public var size: VNSize

    /// Creates a rect with the given `origin` and `size`.
    @inlinable public init(origin: VNPoint, size: VNSize) {
        self.origin = origin
        self.size = size
    }

    /// Creates a rect from scalar components.
    @inlinable public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = VNPoint(x: x, y: y)
        self.size = VNSize(width: width, height: height)
    }

    /// The zero rect (origin at (0,0), size 0×0).
    public static let zero = VNRect(origin: .zero, size: .zero)

    // MARK: - Edges

    @inlinable public var minX: Double { origin.x }
    @inlinable public var minY: Double { origin.y }
    @inlinable public var maxX: Double { origin.x + size.width }
    @inlinable public var maxY: Double { origin.y + size.height }
    @inlinable public var midX: Double { origin.x + size.width / 2 }
    @inlinable public var midY: Double { origin.y + size.height / 2 }
    @inlinable public var width: Double { size.width }
    @inlinable public var height: Double { size.height }

    /// `true` when `width` or `height` is zero.
    @inlinable public var isEmpty: Bool { size.width == 0 || size.height == 0 }

    /// The center of the rect.
    @inlinable public var center: VNPoint { VNPoint(x: midX, y: midY) }

    // MARK: - Normalisation

    /// A version of the rect with non-negative width and height.
    public var standardized: VNRect {
        var r = self
        if r.size.width < 0 { r.origin.x += r.size.width; r.size.width = -r.size.width }
        if r.size.height < 0 { r.origin.y += r.size.height; r.size.height = -r.size.height }
        return r
    }

    // MARK: - Geometric queries

    /// Returns `true` when `point` lies inside or on the boundary of the rect.
    @inlinable public func contains(_ point: VNPoint) -> Bool {
        let s = standardized
        return point.x >= s.minX && point.x <= s.maxX
            && point.y >= s.minY && point.y <= s.maxY
    }

    /// Returns `true` when `other` is entirely within this rect.
    @inlinable public func contains(_ other: VNRect) -> Bool {
        let s = standardized; let o = other.standardized
        return s.minX <= o.minX && s.maxX >= o.maxX
            && s.minY <= o.minY && s.maxY >= o.maxY
    }

    /// Returns `true` when the two rects share any area.
    @inlinable public func intersects(_ other: VNRect) -> Bool {
        let a = standardized; let b = other.standardized
        return a.minX < b.maxX && a.maxX > b.minX
            && a.minY < b.maxY && a.maxY > b.minY
    }

    /// Returns the intersection of the two rects, or `.zero` if they don't intersect.
    public func intersection(_ other: VNRect) -> VNRect {
        let a = standardized; let b = other.standardized
        let x1 = max(a.minX, b.minX); let y1 = max(a.minY, b.minY)
        let x2 = min(a.maxX, b.maxX); let y2 = min(a.maxY, b.maxY)
        guard x2 > x1 && y2 > y1 else { return .zero }
        return VNRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    /// Returns the smallest rect that encloses both rects.
    public func union(_ other: VNRect) -> VNRect {
        let a = standardized; let b = other.standardized
        let x1 = min(a.minX, b.minX); let y1 = min(a.minY, b.minY)
        let x2 = max(a.maxX, b.maxX); let y2 = max(a.maxY, b.maxY)
        return VNRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    /// Returns a rect inset by the given amounts on each side.
    @inlinable public func insetBy(dx: Double, dy: Double) -> VNRect {
        VNRect(x: origin.x + dx, y: origin.y + dy,
               width: size.width - 2 * dx, height: size.height - 2 * dy)
    }

    /// Returns a rect offset by (`dx`, `dy`).
    @inlinable public func offsetBy(dx: Double, dy: Double) -> VNRect {
        VNRect(origin: origin.translated(by: dx, dy), size: size)
    }
}

extension VNRect: CustomStringConvertible {
    public var description: String { "(\(origin.x), \(origin.y), \(size.width), \(size.height))" }
}
