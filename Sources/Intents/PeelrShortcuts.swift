import AppIntents

/// Exposes ready-made phrases in the Shortcuts app and Spotlight.
@available(macOS 14.0, *)
struct PeelrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RemoveBackgroundIntent(),
            phrases: [
                "Remove background with \(.applicationName)",
                "Remove the background using \(.applicationName)"
            ],
            shortTitle: "Remove Background",
            systemImageName: "scissors"
        )
        AppShortcut(
            intent: RemoveBackgroundFromClipboardIntent(),
            phrases: [
                "Remove clipboard background with \(.applicationName)",
                "Clean up my clipboard with \(.applicationName)"
            ],
            shortTitle: "Remove Background from Clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
