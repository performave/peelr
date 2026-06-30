import SwiftUI

@available(macOS 14.0, *)
@main
struct PeelrApp: App {
    @StateObject private var state = AppState()

    init() {
        // Register the global hotkey (⌥⌘B) once at launch.
        HotKeyManager.shared.register {
            AppState.sharedForHotKey?.processClipboard()
        }
    }

    var body: some Scene {
        Window("Peelr", id: "main") {
            MainWindow()
                .environmentObject(state)
                .onAppear { AppState.sharedForHotKey = state }
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Peelr", systemImage: "scissors") {
            Button("Remove BG from Clipboard (⌥⌘B)") {
                state.processClipboard()
            }
            Divider()
            Button("Open Window…") {
                NSApp.activate(ignoringOtherApps: true)
                openMainWindow()
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
    /// Weak-ish bridge so the C hotkey callback can reach the live AppState.
    @MainActor static weak var sharedForHotKey: AppState?
}
