import AppKit
import AVFoundation
import UserNotifications

/// Requests notification authorization, posts "background removed" banners, and plays the
/// chosen sound. A single shared instance is the `UNUserNotificationCenter` delegate.
@available(macOS 14.0, *)
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Retained so an in-flight sound isn't deallocated mid-playback.
    private var audioPlayer: AVAudioPlayer?
    private var systemSound: NSSound?

    private var settings: NotificationSettings { .shared }

    /// Called once at launch: become the delegate and request permission if enabled.
    func configureAtLaunch() {
        UNUserNotificationCenter.current().delegate = self
        requestAuthorizationIfNeeded()
    }

    /// Ask for permission when notifications are enabled (no-op if already decided).
    func requestAuthorizationIfNeeded() {
        guard settings.enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post a notification (and play the sound) for a completed conversion on `channel`.
    func notifyConversionComplete(channel: NotificationChannel) {
        guard settings.isEnabled(channel) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Peelr"
        content.body = channel.notificationBody

        let sound = settings.sound
        if case .systemDefault = sound {
            content.sound = .default
        } else {
            content.sound = nil
            play(sound)
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Play a sound immediately (used by the Settings "Preview" button). Only the on-demand
    /// sounds (system / custom) are previewable; the system default is played by the banner.
    func previewSound(_ sound: NotificationSound) {
        play(sound)
    }

    private func play(_ sound: NotificationSound) {
        switch sound {
        case .none, .systemDefault:
            break
        case .system(let name):
            playSystemSound(named: name)
        case .custom(let fileName):
            let url = SoundStore.customSoundURL(fileName: fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            audioPlayer?.stop()
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        }
    }

    /// `NSSound(named:)` returns a shared cached instance that refuses to `play()` while
    /// already playing. Copy it so back-to-back previews restart cleanly.
    private func playSystemSound(named name: String) {
        systemSound?.stop()
        systemSound = (NSSound(named: name)?.copy() as? NSSound)
        systemSound?.play()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner (and let the system play `.default`) even when Peelr is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
