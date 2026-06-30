import AppKit

/// Registers the Services provider so Peelr appears in the macOS Services menu / right-click.
@available(macOS 14.0, *)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure AppState exists (wires the hotkey bridge), then register the saved hotkey.
        _ = AppState.shared
        HotKeyStore.shared.apply()

        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }
}
