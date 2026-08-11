import Foundation

/// Run-loop modes.
public struct VNRunLoopMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The default mode used by ``VNRunLoop/run()``.
    public static let `default` = VNRunLoopMode(rawValue: "VNDefaultRunLoopMode")
    /// A mode active while tracking events (e.g. mouse drags).
    public static let tracking  = VNRunLoopMode(rawValue: "VNEventTrackingRunLoopMode")
    /// A synthetic mode combining default and tracking.
    public static let common    = VNRunLoopMode(rawValue: "VNRunLoopCommonModes")
}

/// AppKit-style run loop for the main thread.
///
/// ``VNRunLoop`` drives the Vulpina event loop. It processes sources, fires timers,
/// and notifies observers at well-defined points in each iteration. It is always
/// `@MainActor`-isolated and must not be used from background threads.
///
/// Typical lifecycle:
/// ```swift
/// let loop = VNRunLoop.main
/// loop.addSource(mySource)
/// loop.run()  // blocks until stop() is called
/// ```
@MainActor
public final class VNRunLoop {
    /// The shared main run loop.
    public static let main = VNRunLoop()

    private var sources:   [VNRunLoopSource]   = []
    private var timers:    [VNRunLoopTimer]     = []
    private var observers: [VNRunLoopObserver]  = []
    private var _isStopped = false

    private init() {}

    // MARK: - Sources

    /// Adds a source to the run loop.
    public func addSource(_ source: VNRunLoopSource) {
        sources.append(source)
    }

    /// Removes a source from the run loop.
    public func removeSource(_ source: VNRunLoopSource) {
        sources.removeAll { $0 === source }
    }

    // MARK: - Timers

    /// Schedules a timer on the run loop.
    public func addTimer(_ timer: VNRunLoopTimer) {
        timers.append(timer)
    }

    /// Removes a timer from the run loop.
    public func removeTimer(_ timer: VNRunLoopTimer) {
        timers.removeAll { $0 === timer }
    }

    // MARK: - Observers

    /// Adds an observer that receives run-loop activity notifications.
    public func addObserver(_ observer: VNRunLoopObserver) {
        observers.append(observer)
    }

    /// Removes an observer.
    public func removeObserver(_ observer: VNRunLoopObserver) {
        observers.removeAll { $0 === observer }
    }

    // MARK: - Running

    /// Runs the run loop in the `.default` mode until ``stop()`` is called.
    ///
    /// Each iteration:
    /// 1. Notifies `.beforeSources` observers.
    /// 2. Fires any pending ``VNRunLoopSource``s.
    /// 3. Fires any due ``VNRunLoopTimer``s.
    /// 4. Notifies `.beforeWaiting` observers.
    /// 5. Sleeps until the next timer deadline (or 1/60 s if no timers).
    /// 6. Notifies `.afterWaiting` observers.
    public func run() {
        _isStopped = false
        while !_isStopped {
            runOnce()
        }
        notify(.exit)
    }

    /// Stops the run loop after the current iteration completes.
    public func stop() {
        _isStopped = true
    }

    /// Executes a single run-loop iteration. Useful in tests.
    ///
    /// - Returns: `true` if any source fired or any timer fired, `false` if idle.
    @discardableResult
    public func runOnce() -> Bool {
        var didWork = false

        notify(.beforeSources)

        // Fire pending sources.
        for source in sources where source.isPending {
            source.consume()
            source.handler()
            didWork = true
        }

        // Fire due timers.
        let now = Date()
        for timer in timers {
            if timer.checkAndFire(now: now) { didWork = true }
        }

        // Remove invalidated timers.
        timers.removeAll { !$0.isValid }

        notify(.beforeWaiting)

        // Sleep until next timer fires (max 1/60 s for responsiveness).
        let sleepInterval = nextTimerInterval(after: Date())
        Thread.sleep(forTimeInterval: sleepInterval)

        notify(.afterWaiting)

        return didWork
    }

    // MARK: - Private

    private func notify(_ activity: VNRunLoopActivity) {
        for observer in observers { observer.notify(activity) }
    }

    private func nextTimerInterval(after now: Date) -> TimeInterval {
        let max: TimeInterval = 1.0 / 60.0
        let next = timers
            .filter { $0.isValid }
            .map { $0.nextFireDate.timeIntervalSince(now) }
            .filter { $0 > 0 }
            .min()
        guard let next else { return max }
        return Swift.min(max, next)
    }
}
