import SwiftUI

/// Observable store for notification preferences, persisted to `UserDefaults`.
/// Mirrors the `HotKeyStore` pattern so non-UI channels (hotkey, services, intents) can read
/// the shared singleton.
@available(macOS 14.0, *)
@MainActor
final class NotificationSettings: ObservableObject {
    static let shared = NotificationSettings()

    /// Master on/off. Defaults on; permission is requested at first launch.
    @Published var enabled: Bool { didSet { save() } }

    /// Per-channel toggles; a channel notifies only when it and the master switch are on.
    @Published var channels: [NotificationChannel: Bool] { didSet { save() } }

    @Published var sound: NotificationSound { didSet { save() } }

    private enum Keys {
        static let enabled = "notify.enabled"
        static let sound = "notify.sound"
        static func channel(_ c: NotificationChannel) -> String { "notify.channel.\(c.rawValue)" }
    }

    init() {
        let d = UserDefaults.standard
        // Default everything on for a fresh install (no stored value yet).
        enabled = d.object(forKey: Keys.enabled) as? Bool ?? true
        var channels: [NotificationChannel: Bool] = [:]
        for c in NotificationChannel.allCases {
            channels[c] = d.object(forKey: Keys.channel(c)) as? Bool ?? true
        }
        self.channels = channels
        if let stored = d.string(forKey: Keys.sound) {
            sound = NotificationSound(storageString: stored)
        } else {
            sound = .systemDefault
        }
    }

    func isEnabled(_ channel: NotificationChannel) -> Bool {
        enabled && (channels[channel] ?? true)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: Keys.enabled)
        for c in NotificationChannel.allCases {
            d.set(channels[c] ?? true, forKey: Keys.channel(c))
        }
        d.set(sound.storageString, forKey: Keys.sound)
    }
}
