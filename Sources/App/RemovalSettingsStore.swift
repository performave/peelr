import Foundation

/// Persists background-removal settings so every entry point shares one configuration:
/// the editor window, the global hotkey, the menu-bar button, and the clipboard Shortcuts
/// action all read/write the same values. (The parameterized "Remove Background" Shortcuts
/// action keeps its own per-action parameters, as Shortcuts users expect.)
enum RemovalSettingsStore {
    private static let modeKey = "settings.mode"
    private static let toleranceKey = "settings.tolerance"
    private static let featherKey = "settings.feather"
    private static let protectKey = "settings.protectInterior"

    static func load() -> RemovalSettings {
        let d = UserDefaults.standard
        var s = RemovalSettings()
        if let raw = d.string(forKey: modeKey), let mode = RemovalMode(rawValue: raw) { s.mode = mode }
        if d.object(forKey: toleranceKey) != nil { s.tolerance = d.double(forKey: toleranceKey) }
        if d.object(forKey: featherKey) != nil { s.feather = d.double(forKey: featherKey) }
        if d.object(forKey: protectKey) != nil { s.protectInterior = d.bool(forKey: protectKey) }
        return s
    }

    static func save(_ s: RemovalSettings) {
        let d = UserDefaults.standard
        d.set(s.mode.rawValue, forKey: modeKey)
        d.set(s.tolerance, forKey: toleranceKey)
        d.set(s.feather, forKey: featherKey)
        d.set(s.protectInterior, forKey: protectKey)
    }
}
