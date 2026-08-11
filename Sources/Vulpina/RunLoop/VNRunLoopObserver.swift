/// Activity flags that an observer can subscribe to.
public struct VNRunLoopActivity: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// About to process sources and timers.
    public static let beforeSources  = VNRunLoopActivity(rawValue: 1 << 0)
    /// About to block waiting for sources.
    public static let beforeWaiting  = VNRunLoopActivity(rawValue: 1 << 1)
    /// Just woke up from waiting.
    public static let afterWaiting   = VNRunLoopActivity(rawValue: 1 << 2)
    /// Run loop is about to exit.
    public static let exit           = VNRunLoopActivity(rawValue: 1 << 3)
    /// Convenience: all activities.
    public static let allActivities  = VNRunLoopActivity(rawValue: ~0)
}

/// Observes specific run-loop activities.
///
/// Add an observer to a ``VNRunLoop`` with ``VNRunLoop/addObserver(_:)``. The
/// observer's ``handler`` is called on the main actor at each matching activity.
@MainActor
public final class VNRunLoopObserver {
    /// The activities this observer watches.
    public let activities: VNRunLoopActivity
    /// Called on the main actor at each matching activity.
    public let handler: @MainActor (VNRunLoopActivity) -> Void

    /// Creates an observer.
    ///
    /// - Parameters:
    ///   - activities: Which activity flags trigger the handler.
    ///   - handler: Closure invoked with the specific activity that fired.
    public init(activities: VNRunLoopActivity,
                handler: @escaping @MainActor (VNRunLoopActivity) -> Void) {
        self.activities = activities
        self.handler = handler
    }

    func notify(_ activity: VNRunLoopActivity) {
        guard activities.contains(activity) else { return }
        handler(activity)
    }
}
