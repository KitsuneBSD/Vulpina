import ClibX11
import ClibXext
import Vulpina

/// X11 backend for Vulpina.
///
/// Create one instance and pass it to `VNApplication(backend:)`:
///
/// ```swift
/// import VulpinaX11
/// let backend = VNX11Backend()
/// let app = VNApplication(backend: backend)
/// ```
///
/// Requires `DISPLAY` to be set (standard Xlib convention).
@MainActor
public final class VNX11Backend: VNBackend {

    // MARK: - Internal state

    // nonisolated(unsafe): only ever accessed on the main actor, but deinit
    // must close the display outside the actor-isolation check.
    nonisolated(unsafe) private let _display: OpaquePointer
    var display: OpaquePointer { _display }
    let screen: Int32
    private weak var runLoop: VNRunLoop?
    private var wmDeleteWindow: Atom = 0
    /// Retained so event dispatch can forward resize / expose to it.
    private(set) var surface: VNX11Surface?

    // MARK: - Init / deinit

    public init() {
        guard let dpy = XOpenDisplay(nil) else {
            fatalError("VulpinaX11: XOpenDisplay failed — is DISPLAY set?")
        }
        _display = dpy
        screen   = XDefaultScreen(dpy)
        XrmInitialize()
    }

    deinit {
        XCloseDisplay(_display)
    }

    // MARK: - VNBackend

    public var backingScaleFactor: Double {
        guard let rm = XResourceManagerString(display) else { return 1.0 }
        guard let db = XrmGetStringDatabase(rm) else { return 1.0 }
        defer { XrmDestroyDatabase(db) }
        var typeCStr: UnsafeMutablePointer<CChar>? = nil
        var value = XrmValue()
        guard XrmGetResource(db, "Xft.dpi", "Xft.Dpi", &typeCStr, &value) != 0,
              let addr = value.addr,
              let dpi = Double(String(cString: addr))
        else { return 1.0 }
        return max(1.0, dpi / 96.0)
    }

    public func registerEventSource(with runLoop: VNRunLoop) {
        // v1 resolution of P1: polling via the beforeWaiting observer installed
        // in VNApplication.run(). An fd-based source (select/poll on
        // XConnectionNumber) is deferred until a backend needs sub-60Hz latency.
        self.runLoop = runLoop
    }

    public func pollEvents() {
        while XPending(display) > 0 {
            var event = XEvent()
            XNextEvent(display, &event)
            handleEvent(&event)
        }
    }

    public func makeSurface(widthPixels: Int, heightPixels: Int, title: String) -> any VNSurface {
        let root  = XRootWindow(display, screen)
        let black = XBlackPixel(display, screen)
        let white = XWhitePixel(display, screen)

        let win = XCreateSimpleWindow(
            display, root,
            0, 0,
            CUnsignedInt(widthPixels), CUnsignedInt(heightPixels),
            0, black, white)

        // Register WM_DELETE_WINDOW so the backend learns about window-close
        // requests (D12: server-side decorations, WM draws title bar).
        wmDeleteWindow = XInternAtom(display, "WM_DELETE_WINDOW", 0)
        var wdwAtom = wmDeleteWindow
        XSetWMProtocols(display, win, &wdwAtom, 1)

        _ = title.withCString { XStoreName(display, win, $0) }
        XSelectInput(display, win,
                     ExposureMask | StructureNotifyMask |
                     KeyPressMask | KeyReleaseMask |
                     ButtonPressMask | ButtonReleaseMask | PointerMotionMask)
        XMapWindow(display, win)
        XFlush(display)

        let visual = XDefaultVisual(display, screen)
        let depth  = Int32(XDefaultDepth(display, screen))
        let hasSHM = XShmQueryExtension(display) != 0

        let s = VNX11Surface(
            display: display, window: win,
            visual: visual, screen: screen, depth: depth,
            hasSHM: hasSHM)
        surface = s
        return s
    }

    // MARK: - Mouse tracking

    // Track whether button 1 is held so MotionNotify can emit drag vs. move.
    private var _button1Down = false
    private var _button3Down = false

    // MARK: - Event dispatch

    private func handleEvent(_ event: inout XEvent) {
        switch Int32(event.type) {
        case Expose:
            if event.xexpose.count == 0 {
                surface?.didExpose()
            }

        case ConfigureNotify:
            let w = Int(event.xconfigure.width)
            let h = Int(event.xconfigure.height)
            if w > 0 && h > 0 {
                surface?.didResize(width: w, height: h)
            }

        case ButtonPress:
            let btn = Int32(event.xbutton.button)
            let loc = windowPoint(x: Int(event.xbutton.x), y: Int(event.xbutton.y))
            let mods = modifierFlags(state: event.xbutton.state)
            if btn == 4 {
                deliver(VNEvent(type: .scrollWheel, locationInWindow: loc,
                                scrollDeltaX: 0, scrollDeltaY: 3, modifierFlags: mods))
            } else if btn == 5 {
                deliver(VNEvent(type: .scrollWheel, locationInWindow: loc,
                                scrollDeltaX: 0, scrollDeltaY: -3, modifierFlags: mods))
            } else if btn == 6 {
                deliver(VNEvent(type: .scrollWheel, locationInWindow: loc,
                                scrollDeltaX: -3, scrollDeltaY: 0, modifierFlags: mods))
            } else if btn == 7 {
                deliver(VNEvent(type: .scrollWheel, locationInWindow: loc,
                                scrollDeltaX: 3, scrollDeltaY: 0, modifierFlags: mods))
            } else if btn == 1 {
                _button1Down = true
                deliver(VNEvent(type: .mouseDown, locationInWindow: loc, modifierFlags: mods))
            } else if btn == 3 {
                _button3Down = true
                deliver(VNEvent(type: .rightMouseDown, locationInWindow: loc, modifierFlags: mods))
            }

        case ButtonRelease:
            let btn = Int32(event.xbutton.button)
            let loc = windowPoint(x: Int(event.xbutton.x), y: Int(event.xbutton.y))
            let mods = modifierFlags(state: event.xbutton.state)
            if btn == 1 {
                _button1Down = false
                deliver(VNEvent(type: .mouseUp, locationInWindow: loc, modifierFlags: mods))
            } else if btn == 3 {
                _button3Down = false
                deliver(VNEvent(type: .rightMouseUp, locationInWindow: loc, modifierFlags: mods))
            }

        case MotionNotify:
            let loc = windowPoint(x: Int(event.xmotion.x), y: Int(event.xmotion.y))
            let mods = modifierFlags(state: event.xmotion.state)
            if _button1Down {
                deliver(VNEvent(type: .mouseDragged, locationInWindow: loc, modifierFlags: mods))
            } else if _button3Down {
                deliver(VNEvent(type: .rightMouseDragged, locationInWindow: loc, modifierFlags: mods))
            } else {
                deliver(VNEvent(type: .mouseMoved, locationInWindow: loc, modifierFlags: mods))
            }

        case KeyPress:
            let (code, chars, mods) = keyEvent(&event)
            deliver(VNEvent(type: .keyDown, keyCode: code, characters: chars,
                            modifierFlags: mods))

        case KeyRelease:
            let (code, chars, mods) = keyEvent(&event)
            deliver(VNEvent(type: .keyUp, keyCode: code, characters: chars,
                            modifierFlags: mods))

        case ClientMessage:
            if event.xclient.data.l.0 == Int(wmDeleteWindow) {
                runLoop?.stop()
            }

        default:
            break
        }
    }

    // MARK: - Translation helpers

    /// Converts X11 pixel coords (top-left, y-down) → window points (bottom-left, y-up).
    private func windowPoint(x: Int, y: Int) -> VNPoint {
        let scale = backingScaleFactor
        let heightPts = Double(surface?.heightPixels ?? 0) / scale
        return VNPoint(x: Double(x) / scale,
                       y: heightPts - Double(y) / scale)
    }

    private func modifierFlags(state: UInt32) -> VNModifierFlags {
        var flags = VNModifierFlags()
        if state & UInt32(ShiftMask)   != 0 { flags.insert(.shift) }
        if state & UInt32(ControlMask) != 0 { flags.insert(.control) }
        if state & UInt32(Mod1Mask)    != 0 { flags.insert(.option) }
        if state & UInt32(Mod4Mask)    != 0 { flags.insert(.command) }
        if state & UInt32(LockMask)    != 0 { flags.insert(.capsLock) }
        return flags
    }

    private func keyEvent(_ event: inout XEvent)
        -> (code: UInt16, characters: String, modifierFlags: VNModifierFlags)
    {
        let code = UInt16(event.xkey.keycode)
        let mods = modifierFlags(state: event.xkey.state)
        // Look up the printable string for this key.
        var buf = [CChar](repeating: 0, count: 32)
        var keySym: KeySym = 0
        let len = XLookupString(&event.xkey, &buf, Int32(buf.count), &keySym, nil)
        let chars: String
        if len > 0 {
            chars = String(cString: buf)
        } else {
            chars = ""
        }
        return (code, chars, mods)
    }

    private func deliver(_ event: VNEvent) {
        surface?.onEvent?(event)
    }
}
