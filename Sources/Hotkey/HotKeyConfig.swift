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
            let keyCode = UInt32(d.integer(forKey: Keys.keyCode))
            let modifiers = UInt32(d.integer(forKey: Keys.modifiers))
            config = HotKeyConfig(
                enabled: d.bool(forKey: Keys.enabled),
                keyCode: keyCode,
                carbonModifiers: modifiers,
                // Recompute from the key code so older saves with a shifted glyph
                // (e.g. "$" instead of "4") are corrected in place.
                display: HotKeyFormatting.display(carbonModifiers: modifiers, keyCode: keyCode)
            )
        } else {
            config = .default
        }
    }

    /// Register the current hotkey (called at launch and on every change).
    func apply() {
        HotKeyManager.shared.update(config) {
            AppState.sharedForHotKey?.processClipboard(channel: .hotkey)
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

    static func modifierFlags(fromCarbon carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    static func display(carbonModifiers: UInt32, keyCode: UInt32) -> String {
        display(flags: modifierFlags(fromCarbon: carbonModifiers), keyCode: keyCode)
    }

    static func display(flags: NSEvent.ModifierFlags, keyCode: UInt32) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += keyLabel(for: keyCode)
        return s
    }

    /// Human-readable label for a virtual key code, ignoring modifiers so the base
    /// key is shown (e.g. "4" rather than the shifted "$").
    static func keyLabel(for keyCode: UInt32) -> String {
        if let named = specialKeys[Int(keyCode)] { return named }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = unsafeBitCast(layoutPtr, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(keyLayout, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                                    0, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeyState, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// Keys whose label isn't a printable character.
    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
