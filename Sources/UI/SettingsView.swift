import SwiftUI

@available(macOS 14.0, *)
struct SettingsView: View {
    @EnvironmentObject var hotKeys: HotKeyStore

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable global hotkey", isOn: Binding(
                    get: { hotKeys.config.enabled },
                    set: { hotKeys.config.enabled = $0 }
                ))
                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotKeyRecorder(config: $hotKeys.config)
                        .disabled(!hotKeys.config.enabled)
                }
                Text("Processes the image on the clipboard in place. Works system-wide; no Accessibility permission required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}

/// A button that captures the next key chord and stores it in the config.
@available(macOS 14.0, *)
struct HotKeyRecorder: View {
    @Binding var config: HotKeyConfig
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press keys…" : config.display)
                .frame(minWidth: 80)
                .monospaced()
        }
        .buttonStyle(.bordered)
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore lone modifier presses / require at least one modifier for a global hotkey.
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil }
            config = HotKeyConfig(
                enabled: config.enabled,
                keyCode: UInt32(event.keyCode),
                carbonModifiers: HotKeyFormatting.carbonModifiers(from: mods),
                display: HotKeyFormatting.display(flags: mods, keyCode: UInt32(event.keyCode))
            )
            stop()
            return nil // swallow the event
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
