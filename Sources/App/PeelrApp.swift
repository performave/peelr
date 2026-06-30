import SwiftUI

@available(macOS 14.0, *)
@main
struct PeelrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared
    @StateObject private var hotKeys = HotKeyStore.shared

    var body: some Scene {
        Window("Peelr", id: "main") {
            MainWindow()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(hotKeys)
        }

        MenuBarExtra("Peelr", systemImage: "scissors") {
            Button(hotKeys.config.enabled
                   ? "Remove BG from Clipboard (\(hotKeys.config.display))"
                   : "Remove BG from Clipboard") {
                state.processClipboard()
            }
            Divider()
            Button("Open Window…") {
                NSApp.activate(ignoringOtherApps: true)
                openMainWindow()
            }
            SettingsLink {
                Text("Settings…")
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    private func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@available(macOS 14.0, *)
extension AppState {
    /// Weak bridge so the C hotkey callback and Services provider can reach the live AppState.
    @MainActor static weak var sharedForHotKey: AppState?
}
