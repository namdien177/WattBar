import AppKit

/// Plain AppKit entry point: a SwiftUI `App` needs a scene, and an empty Settings scene shows a stray window.
@main
enum WattBarApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(monitor: PowerMonitor())
    }
}
