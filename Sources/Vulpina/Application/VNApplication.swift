/// The central object that manages the application's event loop and lifecycle.
///
/// Create exactly one instance in `main.swift`, set a ``VNApplicationDelegate``,
/// then call ``run()``:
///
/// ```swift
/// @main struct MyApp {
///     static func main() async {
///         await MainActor.run {
///             let app = VNApplication(backend: MyBackend())
///             app.delegate = MyDelegate()
///             app.run()
///         }
///     }
/// }
/// ```
///
/// `VNApplication` owns the ``VNRunLoop/main`` singleton. It installs a
/// `.beforeWaiting` observer that polls the backend for events each iteration,
/// ensuring the event-source pattern works even on backends that use an
/// in-process signal rather than a file descriptor.
@MainActor
public final class VNApplication {
    /// The backend that drives windowing and event delivery.
    public let backend: any VNBackend

    /// The object that receives lifecycle callbacks.
    public weak var delegate: (any VNApplicationDelegate)?

    /// The run loop that drives this application.
    public let runLoop: VNRunLoop = .main

    /// Creates the application with the given backend.
    ///
    /// - Parameter backend: The display-server backend to use.
    public init(backend: any VNBackend) {
        self.backend = backend
    }

    /// Starts the run loop. Blocks until ``terminate()`` is called.
    ///
    /// Calls ``VNApplicationDelegate/applicationDidFinishLaunching(_:)`` before
    /// entering the loop, and ``VNApplicationDelegate/applicationWillTerminate(_:)``
    /// after the loop exits.
    public func run() {
        // Let the backend register its event source (e.g. X11 connection fd).
        backend.registerEventSource(with: runLoop)

        // Poll backend events on every iteration before the run loop sleeps.
        let pollObserver = VNRunLoopObserver(activities: .beforeWaiting) { [weak self] _ in
            self?.backend.pollEvents()
        }
        runLoop.addObserver(pollObserver)

        // Schedule the launch callback as a one-shot source so that terminate()
        // called from within the delegate is honored: the flag is set during
        // runOnce(), before the next iteration check, so the loop exits cleanly.
        // Calling the delegate directly before runLoop.run() would race with
        // _isStopped being reset to false at the top of run().
        let launchSource = VNRunLoopSource { [weak self] in
            guard let self else { return }
            self.delegate?.applicationDidFinishLaunching(self)
        }
        runLoop.addSource(launchSource)
        launchSource.signal()

        runLoop.run()
        runLoop.removeSource(launchSource)
        delegate?.applicationWillTerminate(self)
    }

    /// Stops the run loop, causing ``run()`` to return.
    public func terminate() {
        runLoop.stop()
    }
}
