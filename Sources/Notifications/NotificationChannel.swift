import Foundation

/// The invocation paths that can post a "background removed" notification. These are the
/// "invisible" entry points where the app has no visible window, so a banner is the only
/// feedback the user gets. The editor window and menu-bar button intentionally don't notify.
enum NotificationChannel: String, CaseIterable, Sendable {
    case hotkey
    case shortcuts
    case services

    /// Label shown next to the per-channel toggle in Settings.
    var displayName: String {
        switch self {
        case .hotkey: return "Global hotkey"
        case .shortcuts: return "Shortcuts"
        case .services: return "Services / right-click"
        }
    }

    /// Body text for the posted notification.
    var notificationBody: String {
        switch self {
        case .hotkey, .shortcuts:
            return "Background removed and copied to the clipboard."
        case .services:
            return "Background removed."
        }
    }
}
