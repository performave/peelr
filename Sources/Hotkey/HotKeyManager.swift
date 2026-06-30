import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via Carbon `RegisterEventHotKey`, which (unlike
/// `NSEvent` global monitors) does not require Accessibility permission.
final class HotKeyManager {

    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    /// (Re)apply a configuration: unregister any current hotkey, then register the new one
    /// if it is enabled. Safe to call repeatedly as the user edits the shortcut.
    func update(_ config: HotKeyConfig, action: @escaping () -> Void) {
        unregister()
        self.handler = action
        guard config.enabled else { return }
        installEventHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x50454C52 /* "PELR" */), id: 1)
        RegisterEventHotKey(config.keyCode, config.carbonModifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.id == 1 {
                DispatchQueue.main.async { manager.handler?() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
