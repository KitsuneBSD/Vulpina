import Testing
@testable import Vulpina

// MARK: - Test helpers

private final class RecordingSurface: VNSurface {
    var lastFramebuffer: VNFramebuffer?
    var onNeedsRedraw: (@MainActor () -> Void)? = nil
    @MainActor func present(_ framebuffer: VNFramebuffer) {
        lastFramebuffer = framebuffer
    }
}

private final class FilledView: VNView {
    var color: VNColor
    init(frame: VNRect, color: VNColor) {
        self.color = color
        super.init(frame: frame)
    }
    override func draw(_ context: VNGraphicsContext) {
        var p = VNPath()
        p.move(to: VNPoint(x: bounds.minX, y: bounds.minY))
        p.line(to: VNPoint(x: bounds.maxX, y: bounds.minY))
        p.line(to: VNPoint(x: bounds.maxX, y: bounds.maxY))
        p.line(to: VNPoint(x: bounds.minX, y: bounds.maxY))
        p.close()
        context.fill(p, color: color)
    }
}

// MARK: - VNView hierarchy

@Suite("VNView hierarchy")
struct VNViewHierarchyTests {
    @Test @MainActor func frameAndBounds() {
        let r = VNRect(x: 10, y: 20, width: 100, height: 50)
        let v = VNView(frame: r)
        #expect(v.frame == r)
        #expect(v.bounds == VNRect(x: 0, y: 0, width: 100, height: 50))
    }

    @Test @MainActor func addSubview() {
        let parent = VNView(frame: VNRect(x: 0, y: 0, width: 200, height: 200))
        let child  = VNView(frame: VNRect(x: 10, y: 10, width: 50, height: 50))
        parent.addSubview(child)
        #expect(parent.subviews.count == 1)
        #expect(parent.subviews[0] === child)
        #expect(child.superview === parent)
    }

    @Test @MainActor func removeFromSuperview() {
        let parent = VNView(frame: VNRect(x: 0, y: 0, width: 200, height: 200))
        let child  = VNView(frame: VNRect(x: 0, y: 0, width: 50, height: 50))
        parent.addSubview(child)
        child.removeFromSuperview()
        #expect(parent.subviews.isEmpty)
        #expect(child.superview == nil)
    }

    @Test @MainActor func addSubviewRemovesFromPreviousParent() {
        let p1 = VNView(frame: VNRect(x: 0, y: 0, width: 200, height: 200))
        let p2 = VNView(frame: VNRect(x: 0, y: 0, width: 200, height: 200))
        let child = VNView(frame: VNRect(x: 0, y: 0, width: 10, height: 10))
        p1.addSubview(child)
        p2.addSubview(child)
        #expect(p1.subviews.isEmpty)
        #expect(p2.subviews.count == 1)
        #expect(child.superview === p2)
    }

    @Test @MainActor func setNeedDisplayPropagates() {
        let root  = VNView(frame: VNRect(x: 0, y: 0, width: 200, height: 200))
        let child = VNView(frame: VNRect(x: 0, y: 0, width: 50, height: 50))
        root.addSubview(child)

        // Clear flags manually to test propagation.
        root.needsDisplay  = false
        child.needsDisplay = false

        child.setNeedsDisplay()
        #expect(child.needsDisplay)
        #expect(root.needsDisplay)
    }

    @Test @MainActor func isFlippedDefaultFalse() {
        let v = VNView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        #expect(!v.isFlipped)
    }
}

// MARK: - VNWindow display

@Suite("VNWindow display")
struct VNWindowDisplayTests {
    @Test @MainActor func displayClearsNeedsDisplay() {
        let surface = RecordingSurface()
        let win = VNWindow(surface: surface, sizePoints: VNSize(width: 100, height: 100), backingScale: 1)
        #expect(win.contentView.needsDisplay)
        win.display()
        #expect(!win.contentView.needsDisplay)
        #expect(surface.lastFramebuffer != nil)
    }

    @Test @MainActor func displaySkipsWhenClean() {
        let surface = RecordingSurface()
        let win = VNWindow(surface: surface, sizePoints: VNSize(width: 10, height: 10), backingScale: 1)
        win.display()  // first pass clears the flag
        surface.lastFramebuffer = nil
        win.display()  // should be a no-op
        #expect(surface.lastFramebuffer == nil)
    }

    @Test @MainActor func contentViewFillsWindow() {
        // A red 10×10 window → all pixels should be red.
        let surface = RecordingSurface()
        let win = VNWindow(surface: surface, sizePoints: VNSize(width: 10, height: 10), backingScale: 1)
        let red = FilledView(frame: VNRect(x: 0, y: 0, width: 10, height: 10), color: .init(red: 1, green: 0, blue: 0, alpha: 1))
        win.contentView.addSubview(red)
        win.display()

        let fb = surface.lastFramebuffer!
        // Check a few pixels are red.
        for y in 0..<10 {
            for x in 0..<10 {
                let p = fb.pixel(x: x, y: y)
                #expect(p.r > 200, "pixel (\(x),\(y)) red=\(p.r)")
                #expect(p.a > 200, "pixel (\(x),\(y)) alpha=\(p.a)")
            }
        }
    }

    @Test @MainActor func subviewClipsToFrame() {
        // Window 20×20; blue subview occupies only the left half (0..10 × 0..20).
        // Right half pixels (x >= 10) must remain transparent.
        let surface = RecordingSurface()
        let win = VNWindow(surface: surface, sizePoints: VNSize(width: 20, height: 20), backingScale: 1)
        let blue = FilledView(frame: VNRect(x: 0, y: 0, width: 10, height: 20),
                              color: .init(red: 0, green: 0, blue: 1, alpha: 1))
        win.contentView.addSubview(blue)
        win.display()

        let fb = surface.lastFramebuffer!
        // Left column (x=0) should be blue.
        #expect(fb.pixel(x: 0, y: 10).b > 200)
        // Right column (x=15) should be transparent (not painted).
        #expect(fb.pixel(x: 15, y: 10).a == 0)
    }

    @Test @MainActor func subviewZOrder() {
        // Red view behind blue view at the same position; blue should win on top.
        let surface = RecordingSurface()
        let win = VNWindow(surface: surface, sizePoints: VNSize(width: 10, height: 10), backingScale: 1)
        let red  = FilledView(frame: VNRect(x: 0, y: 0, width: 10, height: 10),
                              color: .init(red: 1, green: 0, blue: 0, alpha: 1))
        let blue = FilledView(frame: VNRect(x: 0, y: 0, width: 10, height: 10),
                              color: .init(red: 0, green: 0, blue: 1, alpha: 1))
        win.contentView.addSubview(red)
        win.contentView.addSubview(blue)
        win.display()

        let fb = surface.lastFramebuffer!
        let p = fb.pixel(x: 5, y: 5)
        #expect(p.b > p.r, "blue should be on top: r=\(p.r) b=\(p.b)")
    }

    @Test @MainActor func subviewPositionedCorrectly() {
        // Window 20×20; green subview at (10, 0, 10, 10) in bottom-right quadrant.
        // In pixel space (y-down), bottom-right quadrant is top-right (y 0..9, x 10..19).
        let surface = RecordingSurface()
        let win = VNWindow(surface: surface, sizePoints: VNSize(width: 20, height: 20), backingScale: 1)
        let green = FilledView(frame: VNRect(x: 10, y: 10, width: 10, height: 10),
                               color: .init(red: 0, green: 1, blue: 0, alpha: 1))
        win.contentView.addSubview(green)
        win.display()

        let fb = surface.lastFramebuffer!
        // Pixel-space: the view's bottom-left is at window-y=10 (points), which is
        // pixel-y = windowHeight - 10 - viewHeight = 20 - 10 - 10 = 0.
        // So green occupies pixel rows 0..9, cols 10..19.
        #expect(fb.pixel(x: 15, y: 5).g > 200)   // inside green
        #expect(fb.pixel(x: 5,  y: 5).a  == 0)    // outside (left half), transparent
        #expect(fb.pixel(x: 15, y: 15).a == 0)    // outside (bottom pixel half), transparent
    }

    @Test @MainActor func clipRespectsViewBounds() {
        // A view that tries to draw OUTSIDE its own bounds should be clipped.
        // We create a view with frame 5×5 that draws a 20×20 rectangle.
        let surface = RecordingSurface()
        let win = VNWindow(surface: surface, sizePoints: VNSize(width: 20, height: 20), backingScale: 1)

        final class OversizedView: VNView {
            override func draw(_ context: VNGraphicsContext) {
                var p = VNPath()
                p.move(to: VNPoint(x: -5, y: -5))
                p.line(to: VNPoint(x: 25, y: -5))
                p.line(to: VNPoint(x: 25, y: 25))
                p.line(to: VNPoint(x: -5, y: 25))
                p.close()
                context.fill(p, color: .init(red: 1, green: 0, blue: 0, alpha: 1))
            }
        }

        // Place the view in the top-right 5×5 corner (window coords bottom-left).
        let over = OversizedView(frame: VNRect(x: 15, y: 15, width: 5, height: 5))
        win.contentView.addSubview(over)
        win.display()

        let fb = surface.lastFramebuffer!
        // Pixel space: the view occupies rows 0..4, cols 15..19 (y flipped).
        // Pixels outside that rect must be transparent.
        #expect(fb.pixel(x: 10, y: 10).a == 0)  // well outside
        #expect(fb.pixel(x: 0,  y: 0 ).a == 0)  // top-left of framebuffer
    }
}
