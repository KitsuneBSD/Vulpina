import Foundation

/// Supplies the blocking wait used by ``VNRunLoop``.
///
/// Drivers are intentionally small so platform-specific waiting primitives stay
/// outside the core target. A driver may wait on file descriptors, kernel event
/// queues, or simply use a timed sleep as the portable fallback.
@MainActor
public protocol VNRunLoopDriver: AnyObject {
    /// Waits until an event arrives or `timeout` elapses.
    ///
    /// A `nil` timeout means that the driver may wait indefinitely.
    ///
    /// - Parameter timeout: Maximum wait duration in seconds.
    func wait(timeout: TimeInterval?)

    /// Wakes a blocked wait, if the driver supports explicit wakeups.
    func wake()
}

/// Portable driver used by the core and deterministic tests.
@MainActor
public final class VNSleepRunLoopDriver: VNRunLoopDriver {
    /// Creates a sleep-based driver.
    public init() {}

    public func wait(timeout: TimeInterval?) {
        guard let timeout else { return }
        if timeout > 0 { Thread.sleep(forTimeInterval: timeout) }
    }

    public func wake() {}
}
