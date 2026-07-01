import AppKit

/// Registers the Services provider so Peelr appears in the macOS Services menu / right-click.
@available(macOS 14.0, *)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure AppState exists (wires the hotkey bridge), then register the saved hotkey.
        _ = AppState.shared
        HotKeyStore.shared.apply()

        // Become the notification delegate and request permission (if enabled).
        _ = NotificationSettings.shared
        NotificationManager.shared.configureAtLaunch()

        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        observeWindowActivationPolicy()
    }

    /// Keep running (as a menu-bar agent) after the last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Show the Dock icon only while the editor window is open; drop back to a background
    /// (menu-bar-only) agent when it's closed. The app keeps running either way.
    private func observeWindowActivationPolicy() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Defer so a closing window is excluded from the visibility check.
                DispatchQueue.main.async { self?.updateActivationPolicy() }
            }
        }
        updateActivationPolicy()
    }

    private func updateActivationPolicy() {
        let editorOpen = NSApp.windows.contains {
            $0.isVisible && $0.identifier?.rawValue.contains("main") == true
        }
        let desired: NSApplication.ActivationPolicy = editorOpen ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
        }
    }
}
