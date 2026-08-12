import Testing
@testable import Vulpina

// MARK: - Test helpers

private final class MockSurface: VNSurface {
    var onNeedsRedraw: (@MainActor () -> Void)? = nil
    var onEvent: (@MainActor (VNEvent) -> Void)? = nil
    @MainActor func present(_ fb: VNFramebuffer) {}
}

@MainActor
private func makeWindow(width: Double = 100, height: Double = 100) -> VNWindow {
    VNWindow(surface: MockSurface(),
             sizePoints: VNSize(width: width, height: height),
             backingScale: 1)
}

// MARK: - VNEvent

@Suite("VNEvent")
struct VNEventTests {
    @Test func defaultFields() {
        let e = VNEvent(type: .mouseDown, locationInWindow: VNPoint(x: 10, y: 20))
        #expect(e.type == .mouseDown)
        #expect(e.locationInWindow == VNPoint(x: 10, y: 20))
        #expect(e.scrollDeltaX == 0)
        #expect(e.scrollDeltaY == 0)
        #expect(e.characters == "")
        #expect(e.modifierFlags == [])
        #expect(e.clickCount == 1)
    }

    @Test func modifierFlagsCompose() {
        let flags: VNModifierFlags = [.shift, .control]
        #expect(flags.contains(.shift))
        #expect(flags.contains(.control))
        #expect(!flags.contains(.option))
    }
}

// MARK: - VNView.hitTest

@Suite("VNView hitTest")
struct HitTestTests {
    @Test @MainActor func missOutsideFrame() {
        let v = VNView(frame: VNRect(x: 10, y: 10, width: 50, height: 50))
        #expect(v.hitTest(VNPoint(x: 5, y: 5)) == nil)
        #expect(v.hitTest(VNPoint(x: 65, y: 30)) == nil)
    }

    @Test @MainActor func hitsViewItself() {
        let v = VNView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        let hit = v.hitTest(VNPoint(x: 50, y: 50))
        #expect(hit === v)
    }

    @Test @MainActor func hitsSubviewOnTop() {
        let parent = VNView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        let child  = VNView(frame: VNRect(x: 20, y: 20, width: 40, height: 40))
        parent.addSubview(child)
        // Point inside child (in parent's superview coords = window coords here)
        let hit = parent.hitTest(VNPoint(x: 40, y: 40))
        #expect(hit === child)
    }

    @Test @MainActor func hitsParentBesideSubview() {
        let parent = VNView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        let child  = VNView(frame: VNRect(x: 50, y: 50, width: 40, height: 40))
        parent.addSubview(child)
        // Point inside parent but not inside child
        let hit = parent.hitTest(VNPoint(x: 10, y: 10))
        #expect(hit === parent)
    }

    @Test @MainActor func zOrderTopSubviewWins() {
        // Two overlapping subviews; last added = top → should be hit.
        let parent = VNView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        let bottom = VNView(frame: VNRect(x: 0, y: 0, width: 80, height: 80))
        let top    = VNView(frame: VNRect(x: 0, y: 0, width: 80, height: 80))
        parent.addSubview(bottom)
        parent.addSubview(top)
        let hit = parent.hitTest(VNPoint(x: 40, y: 40))
        #expect(hit === top)
    }

    @Test @MainActor func deeplyNestedHit() {
        let a = VNView(frame: VNRect(x: 0,  y: 0,  width: 100, height: 100))
        let b = VNView(frame: VNRect(x: 10, y: 10, width: 80,  height: 80))
        let c = VNView(frame: VNRect(x: 10, y: 10, width: 40,  height: 40))
        a.addSubview(b); b.addSubview(c)
        // Point (30, 30) in a's coords → (20, 20) in b → (10, 10) in c → inside c
        let hit = a.hitTest(VNPoint(x: 30, y: 30))
        #expect(hit === c)
    }
}

// MARK: - VNView coordinate conversion

@Suite("VNView coordinate conversion")
struct CoordinateConversionTests {
    @Test @MainActor func convertToWindowSimple() {
        let v = VNView(frame: VNRect(x: 30, y: 40, width: 50, height: 50))
        // Local (0, 0) → window (30, 40)
        let w = v.convert(VNPoint(x: 0, y: 0), to: nil)
        #expect(abs(w.x - 30) < 0.001)
        #expect(abs(w.y - 40) < 0.001)
    }

    @Test @MainActor func convertFromWindowSimple() {
        let v = VNView(frame: VNRect(x: 30, y: 40, width: 50, height: 50))
        // Window (30, 40) → local (0, 0)
        let l = v.convert(VNPoint(x: 30, y: 40), from: nil)
        #expect(abs(l.x) < 0.001)
        #expect(abs(l.y) < 0.001)
    }

    @Test @MainActor func convertBetweenSiblings() {
        let parent = VNView(frame: VNRect(x: 0, y: 0, width: 200, height: 200))
        let a = VNView(frame: VNRect(x: 10, y: 20, width: 50, height: 50))
        let b = VNView(frame: VNRect(x: 70, y: 90, width: 50, height: 50))
        parent.addSubview(a); parent.addSubview(b)
        // a-local (5, 5) → b-local: window = (15, 25); b-local = (15-70, 25-90) = (-55, -65)
        let inB = a.convert(VNPoint(x: 5, y: 5), to: b)
        #expect(abs(inB.x - (-55)) < 0.001)
        #expect(abs(inB.y - (-65)) < 0.001)
    }

    @Test @MainActor func convertNestedToWindow() {
        let root  = VNView(frame: VNRect(x: 0,  y: 0,  width: 200, height: 200))
        let child = VNView(frame: VNRect(x: 50, y: 60, width: 100, height: 100))
        let grand = VNView(frame: VNRect(x: 10, y: 10, width: 50,  height: 50))
        root.addSubview(child); child.addSubview(grand)
        // grand-local (5, 5) → window: 5+10+50=65 x, 5+10+60=75 y
        let w = grand.convert(VNPoint(x: 5, y: 5), to: nil)
        #expect(abs(w.x - 65) < 0.001)
        #expect(abs(w.y - 75) < 0.001)
    }

    @Test @MainActor func roundTrip() {
        let parent = VNView(frame: VNRect(x: 20, y: 30, width: 100, height: 100))
        let child  = VNView(frame: VNRect(x: 10, y: 15, width: 50, height: 50))
        parent.addSubview(child)
        let original = VNPoint(x: 12, y: 7)
        let window   = child.convert(original, to: nil)
        let back     = child.convert(window, from: nil)
        #expect(abs(back.x - original.x) < 0.001)
        #expect(abs(back.y - original.y) < 0.001)
    }
}

// MARK: - VNWindow event dispatch

@Suite("VNWindow event dispatch")
struct WindowEventDispatchTests {

    private final class RecordingView: VNView {
        var events: [VNEventType] = []
        var lastLocation: VNPoint = .zero
        override func mouseDown(with event: VNEvent) {
            events.append(.mouseDown); lastLocation = event.locationInWindow
        }
        override func mouseUp(with event: VNEvent)      { events.append(.mouseUp) }
        override func mouseMoved(with event: VNEvent)   { events.append(.mouseMoved) }
        override func mouseDragged(with event: VNEvent) { events.append(.mouseDragged) }
        override func scrollWheel(with event: VNEvent)  { events.append(.scrollWheel) }
        override func keyDown(with event: VNEvent)      { events.append(.keyDown) }
        override var acceptsFirstResponder: Bool { true }
    }

    @Test @MainActor func mouseDownHitsThenUsesSameTarget() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)

        win.sendEvent(VNEvent(type: .mouseDown, locationInWindow: VNPoint(x: 50, y: 50)))
        win.sendEvent(VNEvent(type: .mouseUp,   locationInWindow: VNPoint(x: 50, y: 50)))
        #expect(view.events == [.mouseDown, .mouseUp])
    }

    @Test @MainActor func mouseUpRoutedToDownTarget() {
        // Mouse up delivered to the same view as mouse down, even if cursor moved.
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)

        win.sendEvent(VNEvent(type: .mouseDown, locationInWindow: VNPoint(x: 50, y: 50)))
        // MouseUp at (200, 200) — outside the view — should still go to view.
        win.sendEvent(VNEvent(type: .mouseUp,   locationInWindow: VNPoint(x: 200, y: 200)))
        #expect(view.events.contains(.mouseUp))
    }

    @Test @MainActor func dragRoutedToDownTarget() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)

        win.sendEvent(VNEvent(type: .mouseDown,    locationInWindow: VNPoint(x: 50, y: 50)))
        win.sendEvent(VNEvent(type: .mouseDragged, locationInWindow: VNPoint(x: 60, y: 60)))
        win.sendEvent(VNEvent(type: .mouseUp,      locationInWindow: VNPoint(x: 60, y: 60)))
        #expect(view.events == [.mouseDown, .mouseDragged, .mouseUp])
    }

    @Test @MainActor func mouseMovedRoutedByHitTest() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 10, y: 10, width: 50, height: 50))
        win.contentView.addSubview(view)

        win.sendEvent(VNEvent(type: .mouseMoved, locationInWindow: VNPoint(x: 30, y: 30)))
        #expect(view.events.contains(.mouseMoved))
    }

    @Test @MainActor func mouseOutsideViewNotDelivered() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 40, height: 40))
        win.contentView.addSubview(view)

        win.sendEvent(VNEvent(type: .mouseMoved, locationInWindow: VNPoint(x: 80, y: 80)))
        #expect(view.events.isEmpty)
    }

    @Test @MainActor func scrollWheelRoutedByHitTest() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)

        win.sendEvent(VNEvent(type: .scrollWheel, locationInWindow: VNPoint(x: 50, y: 50),
                              scrollDeltaY: 3))
        #expect(view.events.contains(.scrollWheel))
    }

    @Test @MainActor func keyEventGoesToFirstResponder() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)

        win.makeFirstResponder(view)
        win.sendEvent(VNEvent(type: .keyDown, characters: "a"))
        #expect(view.events.contains(.keyDown))
    }

    @Test @MainActor func mouseDownMakesFirstResponder() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)

        win.sendEvent(VNEvent(type: .mouseDown, locationInWindow: VNPoint(x: 50, y: 50)))
        #expect(win.firstResponder === view)
    }

    @Test @MainActor func makeFirstResponderCallsDelegate() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)

        let result = win.makeFirstResponder(view)
        #expect(result)
        #expect(win.firstResponder === view)
    }

    @Test @MainActor func makeFirstResponderNilResigns() {
        let win  = makeWindow()
        let view = RecordingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        win.contentView.addSubview(view)
        win.makeFirstResponder(view)

        win.makeFirstResponder(nil)
        #expect(win.firstResponder == nil)
    }
}

// MARK: - Responder chain propagation

@Suite("Responder chain propagation")
struct ResponderChainTests {
    private final class TrackingView: VNView {
        var gotMouse = false
        var gotKey   = false
        override func mouseDown(with event: VNEvent) { gotMouse = true }
        override func keyDown(with event: VNEvent)   { gotKey   = true }
    }

    @Test @MainActor func eventBubblesFromChildToParent() {
        // Child does not override mouseDown; parent should receive it via nextResponder.
        let parent = TrackingView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        let child  = VNView(frame: VNRect(x: 10, y: 10, width: 50, height: 50))
        parent.addSubview(child)

        // Deliver to child; child's default impl calls nextResponder (parent).
        child.mouseDown(with: VNEvent(type: .mouseDown))
        #expect(parent.gotMouse)
    }

    @Test @MainActor func nextResponderIsSuperview() {
        let parent = VNView(frame: VNRect(x: 0, y: 0, width: 100, height: 100))
        let child  = VNView(frame: VNRect(x: 0, y: 0, width: 50, height: 50))
        parent.addSubview(child)
        #expect(child.nextResponder === parent)
    }

    @Test @MainActor func nextResponderNilForDetached() {
        let v = VNView(frame: VNRect(x: 0, y: 0, width: 50, height: 50))
        #expect(v.nextResponder == nil)
    }
}
