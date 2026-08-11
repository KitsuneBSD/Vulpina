import Foundation

/// Fill rule for determining the interior of a path.
public enum VNWindingRule: Sendable, Hashable {
    case nonZero
    case evenOdd
}

/// A vector path described as a sequence of elements.
///
/// Coordinates are in point-space (bottom-left origin, y-up).
/// Angles are in radians measured from the positive x-axis, CCW positive.
public struct VNPath: Sendable {
    /// Individual path elements.
    public enum Element: Sendable {
        case moveTo(VNPoint)
        case lineTo(VNPoint)
        /// Cubic Bézier: (control1, control2, end).
        case cubicTo(VNPoint, VNPoint, VNPoint)
        /// Quadratic Bézier: (control, end).
        case quadTo(VNPoint, VNPoint)
        /// Circular arc: center, radius, startAngle, endAngle (radians), clockwise.
        case arcTo(center: VNPoint, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
        case close
    }

    public private(set) var elements: [Element] = []
    public var windingRule: VNWindingRule

    public init(windingRule: VNWindingRule = .nonZero) {
        self.windingRule = windingRule
    }

    // MARK: - Building

    public mutating func move(to p: VNPoint) { elements.append(.moveTo(p)) }
    public mutating func line(to p: VNPoint) { elements.append(.lineTo(p)) }
    public mutating func close() { elements.append(.close) }

    /// Appends all elements from `other`, preserving the current winding rule.
    public mutating func appendPath(_ other: VNPath) {
        elements.append(contentsOf: other.elements)
    }

    public mutating func addCurve(to end: VNPoint, control1: VNPoint, control2: VNPoint) {
        elements.append(.cubicTo(control1, control2, end))
    }

    public mutating func addQuadCurve(to end: VNPoint, control: VNPoint) {
        elements.append(.quadTo(control, end))
    }

    /// Appends a circular arc.
    ///
    /// - Parameters:
    ///   - center: Center of the circle.
    ///   - radius: Radius in points.
    ///   - startAngle: Start angle in radians (CCW from positive x-axis).
    ///   - endAngle: End angle in radians.
    ///   - clockwise: `true` = clockwise in math coords (y-up).
    public mutating func addArc(center: VNPoint, radius: Double,
                                startAngle: Double, endAngle: Double,
                                clockwise: Bool) {
        elements.append(.arcTo(center: center, radius: radius,
                               startAngle: startAngle, endAngle: endAngle,
                               clockwise: clockwise))
    }

    // MARK: - Flattening

    /// Returns a path with all curves replaced by straight line segments
    /// approximated to within `tolerance` points.
    public func flattened(tolerance: Double = 0.1) -> VNPath {
        var result = VNPath(windingRule: windingRule)
        var current = VNPoint.zero
        var subpathStart = VNPoint.zero

        for element in elements {
            switch element {
            case .moveTo(let p):
                result.move(to: p)
                current = p
                subpathStart = p
            case .lineTo(let p):
                result.line(to: p)
                current = p
            case .cubicTo(let c1, let c2, let end):
                VNBezierFlattener.flattenCubic(p0: current, p1: c1, p2: c2, p3: end,
                                               tolerance: tolerance) { result.line(to: $0) }
                current = end
            case .quadTo(let c, let end):
                VNBezierFlattener.flattenQuad(p0: current, p1: c, p2: end,
                                              tolerance: tolerance) { result.line(to: $0) }
                current = end
            case .arcTo(let center, let radius, let startAngle, let endAngle, let clockwise):
                VNBezierFlattener.flattenArc(center: center, radius: radius,
                                             startAngle: startAngle, endAngle: endAngle,
                                             clockwise: clockwise,
                                             tolerance: tolerance) { result.line(to: $0) }
                let ea = endAngle
                current = VNPoint(x: center.x + radius * cos(ea), y: center.y + radius * sin(ea))
            case .close:
                result.close()
                // After closing, the pen returns to the subpath start point.
                current = subpathStart
            }
        }
        return result
    }

    // MARK: - Convenience constructors

    /// A closed rectangular path (CCW in math / bottom-left coords).
    public static func rect(_ r: VNRect) -> VNPath {
        var p = VNPath()
        p.move(to: VNPoint(x: r.minX, y: r.minY))
        p.line(to: VNPoint(x: r.maxX, y: r.minY))
        p.line(to: VNPoint(x: r.maxX, y: r.maxY))
        p.line(to: VNPoint(x: r.minX, y: r.maxY))
        p.close()
        return p
    }

    /// A closed ellipse inscribed in `rect` (approximated with 4 cubic Béziers).
    public static func ellipse(in rect: VNRect) -> VNPath {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let k = 0.5522847498  // (4/3)*(√2-1), magic Bézier circle constant
        var p = VNPath()
        p.move(to: VNPoint(x: cx + rx, y: cy))
        p.addCurve(to: VNPoint(x: cx, y: cy + ry),
                   control1: VNPoint(x: cx + rx, y: cy + ry * k),
                   control2: VNPoint(x: cx + rx * k, y: cy + ry))
        p.addCurve(to: VNPoint(x: cx - rx, y: cy),
                   control1: VNPoint(x: cx - rx * k, y: cy + ry),
                   control2: VNPoint(x: cx - rx, y: cy + ry * k))
        p.addCurve(to: VNPoint(x: cx, y: cy - ry),
                   control1: VNPoint(x: cx - rx, y: cy - ry * k),
                   control2: VNPoint(x: cx - rx * k, y: cy - ry))
        p.addCurve(to: VNPoint(x: cx + rx, y: cy),
                   control1: VNPoint(x: cx + rx * k, y: cy - ry),
                   control2: VNPoint(x: cx + rx, y: cy - ry * k))
        p.close()
        return p
    }

    /// A closed rounded rectangle with uniform `cornerRadius`.
    public static func roundedRect(_ rect: VNRect, cornerRadius r: Double) -> VNPath {
        let r = min(r, rect.width / 2, rect.height / 2)
        let k = 0.5522847498 * r
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        var p = VNPath()
        p.move(to: VNPoint(x: minX + r, y: minY))
        // Bottom edge → bottom-right corner
        p.line(to: VNPoint(x: maxX - r, y: minY))
        p.addCurve(to: VNPoint(x: maxX, y: minY + r),
                   control1: VNPoint(x: maxX - r + k, y: minY),
                   control2: VNPoint(x: maxX, y: minY + r - k))
        // Right edge → top-right corner
        p.line(to: VNPoint(x: maxX, y: maxY - r))
        p.addCurve(to: VNPoint(x: maxX - r, y: maxY),
                   control1: VNPoint(x: maxX, y: maxY - r + k),
                   control2: VNPoint(x: maxX - r + k, y: maxY))
        // Top edge → top-left corner
        p.line(to: VNPoint(x: minX + r, y: maxY))
        p.addCurve(to: VNPoint(x: minX, y: maxY - r),
                   control1: VNPoint(x: minX + r - k, y: maxY),
                   control2: VNPoint(x: minX, y: maxY - r + k))
        // Left edge → bottom-left corner
        p.line(to: VNPoint(x: minX, y: minY + r))
        p.addCurve(to: VNPoint(x: minX + r, y: minY),
                   control1: VNPoint(x: minX, y: minY + r - k),
                   control2: VNPoint(x: minX + r - k, y: minY))
        p.close()
        return p
    }
}
