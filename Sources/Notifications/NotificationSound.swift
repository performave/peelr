import AppKit

/// The sound played when a conversion notification fires.
///
/// `.systemDefault` rides the notification's own `UNNotificationSound.default`; every other
/// case is played by `NotificationManager` itself (the banner is posted silent) so we can
/// support arbitrary local audio formats via `AVAudioPlayer`.
enum NotificationSound: Equatable {
    case none
    case systemDefault
    /// A named sound from `/System/Library/Sounds` (e.g. "Glass").
    case system(name: String)
    /// A user-supplied file copied into the app's Application Support directory.
    case custom(fileName: String)

    /// Compact string used for `UserDefaults` persistence.
    var storageString: String {
        switch self {
        case .none: return "none"
        case .systemDefault: return "default"
        case .system(let name): return "system:\(name)"
        case .custom(let fileName): return "custom:\(fileName)"
        }
    }

    init(storageString: String) {
        if storageString == "none" {
            self = .none
        } else if storageString.hasPrefix("system:") {
            self = .system(name: String(storageString.dropFirst("system:".count)))
        } else if storageString.hasPrefix("custom:") {
            self = .custom(fileName: String(storageString.dropFirst("custom:".count)))
        } else {
            self = .systemDefault
        }
    }
}

/// Enumerates system sounds and manages the on-disk copy of a user's custom sound.
enum SoundStore {
    /// Names of the built-in system sounds, e.g. ["Basso", "Blow", "Glass", …].
    static func systemSoundNames() -> [String] {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                   includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "aiff" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// `~/Library/Application Support/Peelr/Sounds`, created on demand.
    static func customSoundsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Peelr/Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Resolves the stored file name of a `.custom` sound to its on-disk URL.
    static func customSoundURL(fileName: String) -> URL {
        customSoundsDirectory().appendingPathComponent(fileName)
    }

    /// Copy a user-picked audio file into our Sounds directory so it keeps working even if the
    /// original is deleted or moved. Removes any previous custom sound. Returns the stored name.
    static func importCustomSound(from url: URL) throws -> String {
        let dir = customSoundsDirectory()
        // Clear out any previous custom sound(s) so we don't accumulate files.
        for existing in (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                       includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: existing)
        }
        // Prefix with a UUID so odd characters / duplicate names can't collide.
        let fileName = "\(UUID().uuidString)-\(url.lastPathComponent)"
        let dest = dir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: url, to: dest)
        return fileName
    }
}
