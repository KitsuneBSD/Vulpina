/// Lifecycle callbacks for ``VNApplication``.
///
/// Adopt this protocol in your application's entry point to respond to
/// application-level events.
@MainActor
public protocol VNApplicationDelegate: AnyObject {
    /// Called after the run loop starts and the backend is ready.
    func applicationDidFinishLaunching(_ application: VNApplication)

    /// Called just before the run loop exits and the process terminates.
    func applicationWillTerminate(_ application: VNApplication)
}

// Default no-op implementations so conformers can omit methods they don't need.
public extension VNApplicationDelegate {
    func applicationDidFinishLaunching(_ application: VNApplication) {}
    func applicationWillTerminate(_ application: VNApplication) {}
}
