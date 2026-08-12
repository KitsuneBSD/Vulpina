import Vulpina
import VulpinaX11

// MARK: - Demo layout constants

private let windowWidth  = 640.0
private let windowHeight = 480.0

private let headerHeight  = 36.0
private let margin        = 16.0
private let cardW         = 140.0
private let cardH         = 90.0
private let circleSize    = 160.0
private let trackerHeight = 120.0

// MARK: - Delegate

@MainActor
final class DemoDelegate: VNApplicationDelegate {
    let app: VNApplication

    init(app: VNApplication) { self.app = app }

    func applicationDidFinishLaunching(_ application: VNApplication) {
        let backend  = application.backend
        let scale    = backend.backingScaleFactor
        let widthPx  = Int((windowWidth  * scale).rounded())
        let heightPx = Int((windowHeight * scale).rounded())

        let surface = backend.makeSurface(widthPixels: widthPx,
                                          heightPixels: heightPx,
                                          title: "Vulpina Demo — M6")
        let window  = VNWindow(surface: surface,
                               sizePoints: VNSize(width: windowWidth, height: windowHeight),
                               backingScale: scale)
        buildUI(in: window)
        window.makeKeyAndOrderFront(runLoop: application.runLoop)
    }

    func applicationWillTerminate(_ application: VNApplication) {}

    // MARK: - View hierarchy

    private func buildUI(in window: VNWindow) {
        let cv = window.contentView

        // Dark background
        cv.addSubview(BackgroundView(frame: VNRect(x: 0, y: 0,
                                                   width: windowWidth,
                                                   height: windowHeight)))

        // Header bar at top
        cv.addSubview(HeaderBar(frame: VNRect(x: 0,
                                              y: windowHeight - headerHeight,
                                              width: windowWidth,
                                              height: headerHeight)))

        // Three color swatch cards (horizontal row)
        let cardColors: [(VNColor, String)] = [
            (VNColor(red: 0.25, green: 0.55, blue: 1.0,  alpha: 1), "Slate Blue"),
            (VNColor(red: 0.95, green: 0.35, blue: 0.3,  alpha: 1), "Coral"),
            (VNColor(red: 0.25, green: 0.80, blue: 0.45, alpha: 1), "Mint"),
        ]
        let cardRowY  = windowHeight - headerHeight - margin - cardH
        let totalW    = Double(cardColors.count) * cardW + Double(cardColors.count - 1) * margin
        var cardX     = (windowWidth - totalW) * 0.5

        for (color, label) in cardColors {
            cv.addSubview(SwatchCard(frame: VNRect(x: cardX, y: cardRowY,
                                                   width: cardW, height: cardH),
                                     fillColor: color, label: label))
            cardX += cardW + margin
        }

        // Mouse tracker row at the bottom (D30: interactive demo)
        let trackerY = margin
        cv.addSubview(MouseTrackerView(frame: VNRect(x: margin, y: trackerY,
                                                     width: windowWidth - margin * 2,
                                                     height: trackerHeight)))

        // Circle cluster above tracker
        let clusterY = trackerY + trackerHeight + margin
        cv.addSubview(CircleClusterView(frame: VNRect(x: margin, y: clusterY,
                                                      width: circleSize,
                                                      height: circleSize)))

        // Stroke sampler grid (right side, same row)
        let samplerX = margin + circleSize + margin
        let samplerW = windowWidth - samplerX - margin
        let samplerH = circleSize
        cv.addSubview(StrokeSamplerView(frame: VNRect(x: samplerX, y: clusterY,
                                                      width: samplerW,
                                                      height: samplerH)))
    }
}

// MARK: - Entry point

MainActor.assumeIsolated {
    let backend = VNX11Backend()
    let app     = VNApplication(backend: backend)
    let delegate = DemoDelegate(app: app)
    app.delegate = delegate
    app.run()
}
