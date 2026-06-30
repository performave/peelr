import SwiftUI
import Carbon.HIToolbox

/// Persisted global-hotkey configuration.
struct HotKeyConfig: Equatable {
    var enabled: Bool
    var keyCode: UInt32          // virtual key code (kVK_*)
    var carbonModifiers: UInt32  // cmdKey | optionKey | ...
    var display: String          // e.g. "⌥⌘B"

    static let `default` = HotKeyConfig(
        enabled: true,
        keyCode: UInt32(kVK_ANSI_B),
        carbonModifiers: UInt32(optionKey | cmdKey),
        display: "⌥⌘B"
    )
}

/// Observable store that persists the hotkey to `UserDefaults` and (re)registers it
/// with `HotKeyManager` whenever it changes.
@available(macOS 14.0, *)
@MainActor
final class HotKeyStore: ObservableObject {
    static let shared = HotKeyStore()

    @Published var config: HotKeyConfig {
        didSet { save(); apply() }
    }

    private enum Keys {
        static let enabled = "hotkey.enabled"
        static let keyCode = "hotkey.keyCode"
        static let modifiers = "hotkey.modifiers"
        static let display = "hotkey.display"
    }

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.keyCode) != nil {
            config = HotKeyConfig(
                enabled: d.bool(forKey: Keys.enabled),
                keyCode: UInt32(d.integer(forKey: Keys.keyCode)),
                carbonModifiers: UInt32(d.integer(forKey: Keys.modifiers)),
                display: d.string(forKey: Keys.display) ?? HotKeyConfig.default.display
            )
        } else {
            config = .default
        }
    }

    /// Register the current hotkey (called at launch and on every change).
    func apply() {
        HotKeyManager.shared.update(config) {
            AppState.sharedForHotKey?.processClipboard()
        }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(config.enabled, forKey: Keys.enabled)
        d.set(Int(config.keyCode), forKey: Keys.keyCode)
        d.set(Int(config.carbonModifiers), forKey: Keys.modifiers)
        d.set(config.display, forKey: Keys.display)
    }
}

/// Conversions between AppKit modifier flags and Carbon modifier masks.
enum HotKeyFormatting {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func display(flags: NSEvent.ModifierFlags, keyCharacters: String?) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += (keyCharacters ?? "?").uppercased()
        return s
    }
}
