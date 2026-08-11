import Foundation

/// A timer that fires on a ``VNRunLoop`` at regular intervals.
///
/// Timers are not rescheduled if they fire late; the next fire date is computed
/// as `lastFire + interval` (AppKit/CFRunLoop semantics).
@MainActor
public final class VNRunLoopTimer {
    /// The interval between firings, in seconds. Zero means fire once.
    public let interval: Double
    /// Called on the main actor each time the timer fires.
    public let handler: @MainActor (VNRunLoopTimer) -> Void
    /// Whether this timer repeats. Non-repeating timers invalidate after the first fire.
    public let repeats: Bool

    private(set) var nextFireDate: Date
    private(set) var isValid: Bool = true

    /// Creates a timer.
    ///
    /// - Parameters:
    ///   - interval: Seconds between firings (or until first firing).
    ///   - repeats: If `false`, the timer fires once then invalidates itself.
    ///   - handler: Closure called on each firing with the timer as argument.
    public init(interval: Double, repeats: Bool = true,
                handler: @escaping @MainActor (VNRunLoopTimer) -> Void) {
        self.interval = interval
        self.repeats = repeats
        self.handler = handler
        self.nextFireDate = Date(timeIntervalSinceNow: interval)
    }

    /// Permanently stops this timer from firing.
    public func invalidate() {
        isValid = false
    }

    /// Fires the timer if it is due. Returns whether it fired.
    func checkAndFire(now: Date) -> Bool {
        guard isValid, now >= nextFireDate else { return false }
        handler(self)
        if repeats {
            // Advance by interval (skip missed firings).
            var next = nextFireDate
            while next <= now { next = next.addingTimeInterval(interval) }
            nextFireDate = next
        } else {
            invalidate()
        }
        return true
    }
}
