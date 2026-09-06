import ClibX11
import ClibXext
import Glibc
import Vulpina

/// An X11 window surface that blits a `VNFramebuffer` to screen.
///
/// Uses MIT-SHM (`XShm`) for zero-copy-to-X11-server blitting when available,
/// falling back to `XPutImage` (one socket copy) otherwise (D27, P2 v1 resolution).
///
/// Pixel conversion: premultiplied RGBA8 (D24) → un-premultiplied BGRA for the
/// X11 TrueColor little-endian layout (R=0xFF0000, G=0x00FF00, B=0x0000FF).
@MainActor
public final class VNX11Surface: VNSurface {

    // MARK: - Stored state

    // Properties accessed in deinit must be nonisolated(unsafe); they are only
    // ever written on the main actor, so data races cannot occur in practice.
    nonisolated(unsafe) private let display: OpaquePointer
    private let window: Window          // UInt — Sendable, no nonisolated needed
    nonisolated(unsafe) private let gc: OpaquePointer
    private let hasSHM: Bool

    private let visual: UnsafeMutablePointer<Visual>?
    private let depth: Int32
    private let backingScale: Double

    private(set) var widthPixels: Int  = 0
    private(set) var heightPixels: Int = 0

    public var onNeedsRedraw: (@MainActor () -> Void)? = nil
    public var onResize: (@MainActor (VNSize) -> Void)? = nil
    public var onEvent: (@MainActor (VNEvent) -> Void)? = nil

    // SHM path (nonisolated(unsafe) for deinit cleanup)
    nonisolated(unsafe) private var shmInfo  = XShmSegmentInfo()
    nonisolated(unsafe) private var shmImage: UnsafeMutablePointer<XImage>? = nil

    // XPutImage fallback (nonisolated(unsafe) for deinit cleanup)
    nonisolated(unsafe) private var putImage:  UnsafeMutablePointer<XImage>? = nil
    nonisolated(unsafe) private var putBuffer: UnsafeMutableRawPointer? = nil

    // MARK: - Init / deinit

    init(display: OpaquePointer, window: Window,
         visual: UnsafeMutablePointer<Visual>?, screen: Int32, depth: Int32,
         hasSHM: Bool, backingScale: Double) {
        self.display  = display
        self.window   = window
        self.visual   = visual
        self.depth    = depth
        self.hasSHM   = hasSHM
        self.backingScale = backingScale
        var gcValues = XGCValues()
        self.gc = XCreateGC(display, window, 0, &gcValues)
    }

    deinit {
        cleanupBuffers()
        XFreeGC(display, gc)
        XDestroyWindow(display, window)
    }

    // MARK: - VNSurface

    public func present(_ framebuffer: VNFramebuffer) {
        let w = framebuffer.widthPixels
        let h = framebuffer.heightPixels
        guard w > 0 && h > 0 else { return }

        ensureBuffer(width: w, height: h)
        convert(framebuffer, width: w, height: h)

        if hasSHM, let img = shmImage {
            XShmPutImage(display, window, gc, img,
                         0, 0, 0, 0,
                         CUnsignedInt(w), CUnsignedInt(h),
                         0 /* no completion event */)
            // XSync blocks until the server has processed all pending requests,
            // guaranteeing it has finished reading the SHM segment before we
            // overwrite it on the next frame (IMM-6).
            XSync(display, 0)
        } else if let img = putImage {
            XPutImage(display, window, gc, img,
                      0, 0, 0, 0,
                      CUnsignedInt(w), CUnsignedInt(h))
            XFlush(display)
        }
    }

    // MARK: - Resize

    func didResize(width: Int, height: Int) {
        guard width != widthPixels || height != heightPixels else { return }
        widthPixels  = width
        heightPixels = height
        cleanupBuffers()    // lazily reallocated on next present()
        onResize?(VNSize(width: Double(width) / backingScale,
                         height: Double(height) / backingScale))
        onNeedsRedraw?()
    }

    func didExpose() {
        onNeedsRedraw?()
    }

    // MARK: - Buffer management

    private func ensureBuffer(width: Int, height: Int) {
        let needsAlloc = hasSHM ? (shmImage == nil) : (putImage == nil)
        let sizeChanged = width != widthPixels || height != heightPixels
        guard needsAlloc || sizeChanged else { return }
        if hasSHM {
            freeSHMBuffer()
            allocSHMBuffer(width: width, height: height)
        } else {
            freePutBuffer()
            allocPutBuffer(width: width, height: height)
        }
        widthPixels  = width
        heightPixels = height
    }

    // MARK: SHM allocation

    private func allocSHMBuffer(width: Int, height: Int) {
        let size  = width * height * 4
        let shmid = shmget(IPC_PRIVATE, size, Int32(IPC_CREAT) | 0o600)
        guard shmid != -1 else { return }

        guard let addr = shmat(shmid, nil, 0),
              Int(bitPattern: addr) != -1
        else { shmctl(shmid, IPC_RMID, nil); return }

        shmInfo.shmid    = shmid
        shmInfo.shmaddr  = addr.assumingMemoryBound(to: CChar.self)
        shmInfo.readOnly = 0

        let img = XShmCreateImage(
            display, visual, UInt32(depth), ZPixmap,
            shmInfo.shmaddr, &shmInfo,
            UInt32(width), UInt32(height))
        guard let img else {
            _ = shmdt(addr)
            shmctl(shmid, IPC_RMID, nil)
            return
        }

        XShmAttach(display, &shmInfo)
        XSync(display, 0)
        // Mark the segment for deletion; it disappears once all processes detach.
        shmctl(shmid, IPC_RMID, nil)
        shmImage = img
    }

    private func freeSHMBuffer() {
        guard let img = shmImage else { return }
        XShmDetach(display, &shmInfo)
        vulpina_ximage_clear_data(img)   // prevent XDestroyImage from freeing SHM memory
        _ = vulpina_XDestroyImage(img)
        if let addr = shmInfo.shmaddr { _ = shmdt(addr) }
        shmImage = nil
        shmInfo  = XShmSegmentInfo()
    }

    // MARK: XPutImage fallback

    private func allocPutBuffer(width: Int, height: Int) {
        let size = width * height * 4
        guard let buf = malloc(size) else { return }
        let img = XCreateImage(
            display, visual, UInt32(depth), ZPixmap, 0,
            buf.assumingMemoryBound(to: CChar.self),
            UInt32(width), UInt32(height),
            32, 0)
        guard let img else { free(buf); return }
        putBuffer = buf
        putImage  = img
    }

    private func freePutBuffer() {
        guard let img = putImage else { return }
        // Nullify data pointer so XDestroyImage doesn't free our malloc'd buffer.
        vulpina_ximage_clear_data(img)
        _ = vulpina_XDestroyImage(img)
        putImage = nil
        if let buf = putBuffer { free(buf) }
        putBuffer = nil
    }

    // nonisolated so deinit can call it without actor-isolation errors.
    nonisolated private func cleanupBuffers() {
        if hasSHM {
            guard let img = shmImage else { return }
            XShmDetach(display, &shmInfo)
            vulpina_ximage_clear_data(img)
            _ = vulpina_XDestroyImage(img)
            if let addr = shmInfo.shmaddr { _ = shmdt(addr) }
            shmImage = nil
            shmInfo = XShmSegmentInfo()
        } else {
            guard let img = putImage else { return }
            vulpina_ximage_clear_data(img)
            _ = vulpina_XDestroyImage(img)
            if let buf = putBuffer { free(buf) }
            putImage = nil
            putBuffer = nil
        }
    }

    // MARK: - Pixel conversion

    /// Converts premultiplied RGBA8 → X11 little-endian BGRA (`UInt32`).
    ///
    /// X11 TrueColor 24-bit on x86-64: bytes in memory = [B, G, R, X],
    /// so `pixel = B | (G << 8) | (R << 16)`.
    private func convert(_ fb: VNFramebuffer, width: Int, height: Int) {
        let dst: UnsafeMutablePointer<UInt32>
        if hasSHM {
            guard let addr = shmInfo.shmaddr else { return }
            dst = UnsafeMutableRawPointer(addr).assumingMemoryBound(to: UInt32.self)
        } else {
            guard let buf = putBuffer else { return }
            dst = buf.assumingMemoryBound(to: UInt32.self)
        }

        fb.bytes.withUnsafeBytes { src in
            let base = src.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0 ..< width * height {
                let o = i &* 4
                let r = base[o], g = base[o &+ 1], b = base[o &+ 2], a = base[o &+ 3]
                let (sr, sg, sb): (UInt32, UInt32, UInt32)
                if a == 0 {
                    (sr, sg, sb) = (0, 0, 0)
                } else if a == 255 {
                    (sr, sg, sb) = (UInt32(r), UInt32(g), UInt32(b))
                } else {
                    let inv = 255.0 / Double(a)
                    sr = UInt32(min(255.0, Double(r) * inv))
                    sg = UInt32(min(255.0, Double(g) * inv))
                    sb = UInt32(min(255.0, Double(b) * inv))
                }
                dst[i] = sb | (sg << 8) | (sr << 16) | (UInt32(a) << 24)
            }
        }
    }
}
