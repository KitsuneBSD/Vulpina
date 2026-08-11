import Foundation

/// A 2D affine transform using row-vector convention (matches Cocoa/CGAffineTransform).
///
/// A point (x, y) transforms to:
/// ```
/// x' = x·a + y·c + tx
/// y' = x·b + y·d + ty
/// ```
public struct VNAffineTransform: Sendable, Hashable {
    public var a, b, c, d, tx, ty: Double

    @inlinable public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = VNAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    @inlinable public func applying(to p: VNPoint) -> VNPoint {
        VNPoint(x: p.x * a + p.y * c + tx, y: p.x * b + p.y * d + ty)
    }

    /// Returns the transform that first applies `self`, then `other`.
    public func concatenating(_ other: VNAffineTransform) -> VNAffineTransform {
        VNAffineTransform(
            a:  a  * other.a + b  * other.c,
            b:  a  * other.b + b  * other.d,
            c:  c  * other.a + d  * other.c,
            d:  c  * other.b + d  * other.d,
            tx: tx * other.a + ty * other.c + other.tx,
            ty: tx * other.b + ty * other.d + other.ty
        )
    }

    public static func translation(x: Double, y: Double) -> VNAffineTransform {
        VNAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(x: Double, y: Double) -> VNAffineTransform {
        VNAffineTransform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    public static func rotation(angle: Double) -> VNAffineTransform {
        let cosA = Foundation.cos(angle), sinA = Foundation.sin(angle)
        return VNAffineTransform(a: cosA, b: sinA, c: -sinA, d: cosA, tx: 0, ty: 0)
    }
}
