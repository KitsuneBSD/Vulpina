import Testing
@testable import Vulpina

// MARK: - VNPoint

@Suite("VNPoint")
struct VNPointTests {
    @Test func zero() {
        #expect(VNPoint.zero.x == 0)
        #expect(VNPoint.zero.y == 0)
    }

    @Test func equality() {
        #expect(VNPoint(x: 1, y: 2) == VNPoint(x: 1, y: 2))
        #expect(VNPoint(x: 1, y: 2) != VNPoint(x: 1, y: 3))
    }

    @Test func translated() {
        let p = VNPoint(x: 3, y: 4).translated(by: -1, 2)
        #expect(p.x == 2)
        #expect(p.y == 6)
    }

    @Test func sendable() {
        let p: VNPoint = .zero
        let _: any Sendable = p
    }

    @Test func description() {
        #expect(VNPoint(x: 1, y: 2).description == "(1.0, 2.0)")
    }
}

// MARK: - VNSize

@Suite("VNSize")
struct VNSizeTests {
    @Test func zero() {
        #expect(VNSize.zero.isEmpty)
    }

    @Test func notEmpty() {
        #expect(!VNSize(width: 1, height: 1).isEmpty)
    }

    @Test func equality() {
        #expect(VNSize(width: 10, height: 20) == VNSize(width: 10, height: 20))
    }
}

// MARK: - VNRect

@Suite("VNRect")
struct VNRectTests {
    let r = VNRect(x: 10, y: 20, width: 100, height: 50)

    @Test func edges() {
        #expect(r.minX == 10)
        #expect(r.minY == 20)
        #expect(r.maxX == 110)
        #expect(r.maxY == 70)
        #expect(r.midX == 60)
        #expect(r.midY == 45)
    }

    @Test func center() {
        #expect(r.center == VNPoint(x: 60, y: 45))
    }

    @Test func containsPoint() {
        #expect(r.contains(VNPoint(x: 10, y: 20)))   // corner
        #expect(r.contains(VNPoint(x: 60, y: 45)))   // center
        #expect(!r.contains(VNPoint(x: 0, y: 0)))
        #expect(!r.contains(VNPoint(x: 111, y: 45)))
    }

    @Test func containsRect() {
        let inner = VNRect(x: 20, y: 30, width: 10, height: 10)
        #expect(r.contains(inner))
        #expect(!inner.contains(r))
    }

    @Test func intersects() {
        let overlap = VNRect(x: 50, y: 30, width: 100, height: 100)
        #expect(r.intersects(overlap))
        let away = VNRect(x: 200, y: 200, width: 10, height: 10)
        #expect(!r.intersects(away))
    }

    @Test func intersection() {
        let other = VNRect(x: 50, y: 30, width: 100, height: 100)
        let i = r.intersection(other)
        #expect(i.minX == 50)
        #expect(i.minY == 30)
        #expect(i.maxX == 110)
        #expect(i.maxY == 70)
    }

    @Test func intersectionNone() {
        let away = VNRect(x: 200, y: 200, width: 10, height: 10)
        #expect(r.intersection(away) == .zero)
    }

    @Test func union() {
        let other = VNRect(x: 0, y: 0, width: 10, height: 10)
        let u = r.union(other)
        #expect(u.minX == 0)
        #expect(u.minY == 0)
        #expect(u.maxX == 110)
        #expect(u.maxY == 70)
    }

    @Test func insetBy() {
        let i = r.insetBy(dx: 5, dy: 10)
        #expect(i.origin.x == 15)
        #expect(i.origin.y == 30)
        #expect(i.width == 90)
        #expect(i.height == 30)
    }

    @Test func offsetBy() {
        let o = r.offsetBy(dx: 5, dy: -5)
        #expect(o.origin.x == 15)
        #expect(o.origin.y == 15)
        #expect(o.size == r.size)
    }

    @Test func standardized() {
        let neg = VNRect(x: 110, y: 70, width: -100, height: -50)
        let s = neg.standardized
        #expect(s.minX == 10)
        #expect(s.minY == 20)
        #expect(s.width == 100)
        #expect(s.height == 50)
    }

    @Test func isEmpty() {
        #expect(VNRect.zero.isEmpty)
        #expect(VNRect(x: 0, y: 0, width: 0, height: 10).isEmpty)
        #expect(!r.isEmpty)
    }
}

// MARK: - VNInsets

@Suite("VNInsets")
struct VNInsetsTests {
    @Test func zero() {
        #expect(VNInsets.zero == VNInsets(top: 0, left: 0, bottom: 0, right: 0))
    }

    @Test func uniform() {
        let i = VNInsets(5)
        #expect(i.top == 5 && i.left == 5 && i.bottom == 5 && i.right == 5)
    }

    @Test func values() {
        let i = VNInsets(top: 1, left: 2, bottom: 3, right: 4)
        #expect(i.top == 1 && i.left == 2 && i.bottom == 3 && i.right == 4)
    }

    @Test func sendable() {
        let i: VNInsets = .zero
        let _: any Sendable = i
    }
}

// MARK: - VNColor

@Suite("VNColor")
struct VNColorTests {
    @Test func namedColors() {
        #expect(VNColor.black == VNColor(red: 0, green: 0, blue: 0))
        #expect(VNColor.white == VNColor(red: 1, green: 1, blue: 1))
        #expect(VNColor.clear.alpha == 0)
    }

    @Test func withAlpha() {
        let c = VNColor.red.withAlpha(0.5)
        #expect(c.red == 1)
        #expect(c.alpha == 0.5)
    }

    @Test func premultiplied() {
        let c = VNColor(red: 1, green: 0.5, blue: 0, alpha: 0.5)
        let p = c.premultiplied
        #expect(p.red == 0.5)
        #expect(p.green == 0.25)
        #expect(p.blue == 0)
        #expect(p.alpha == 0.5)
    }

    @Test func defaultAlpha() {
        let c = VNColor(red: 0.2, green: 0.4, blue: 0.6)
        #expect(c.alpha == 1)
    }

    @Test func sendable() {
        let c: VNColor = .black
        let _: any Sendable = c
    }

    @Test func hashable() {
        var set = Set<VNColor>()
        set.insert(.red)
        set.insert(.red)
        #expect(set.count == 1)
    }
}
