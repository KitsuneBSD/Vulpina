/// A source of events that can be added to a ``VNRunLoop``.
///
/// Sources are fired in the order they signal within a run-loop iteration.
/// A source can be either *manual* (signalled by calling ``signal()``) or backed
/// by a file descriptor watched by the run loop.
@MainActor
public final class VNRunLoopSource {
    /// Called on the main actor when this source fires.
    public let handler: @MainActor () -> Void
    private(set) var isPending: Bool = false

    /// Creates a source with the given handler.
    public init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    /// Marks this source as pending so it fires on the next run-loop pass.
    public func signal() {
        isPending = true
    }

    /// Clears the pending flag (called by ``VNRunLoop`` after firing).
    func consume() {
        isPending = false
    }
}
