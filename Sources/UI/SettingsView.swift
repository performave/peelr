import SwiftUI
import UniformTypeIdentifiers

@available(macOS 14.0, *)
struct SettingsView: View {
    var body: some View {
        TabView {
            Form { GlobalHotkeySection() }
                .formStyle(.grouped)
                .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                BackgroundRemovalSection()
                PhotoModelSection()
            }
            .formStyle(.grouped)
            .tabItem { Label("Removal", systemImage: "scissors") }

            Form { NotificationsSection() }
                .formStyle(.grouped)
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 560, height: 440)
    }
}

/// Global hotkey configuration.
@available(macOS 14.0, *)
private struct GlobalHotkeySection: View {
    @EnvironmentObject var hotKeys: HotKeyStore

    var body: some View {
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
}

/// Background-removal settings, editable without opening the editor window. Bound to the
/// persisted `AppState.settings`, so the global hotkey, menu-bar button, and clipboard
/// Shortcuts action all use these values.
@available(macOS 14.0, *)
private struct BackgroundRemovalSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Section("Background Removal") {
            Picker("Mode", selection: $state.settings.mode) {
                ForEach(RemovalMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading) {
                Text("Tolerance: \(Int(state.settings.tolerance))")
                Slider(value: $state.settings.tolerance, in: 1...100)
            }
            VStack(alignment: .leading) {
                Text("Edge feather: \(state.settings.feather, specifier: "%.1f") px")
                Slider(value: $state.settings.feather, in: 0...8)
            }
            Toggle("Protect interior content", isOn: $state.settings.protectInterior)
                .help("Only remove background connected to the edges. Leaves enclosed regions (like the inside of letters) intact.")

            Text("Applies to the global hotkey, menu-bar button, and clipboard action. Tolerance and feather affect Slide (color-key) mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Controls for the downloadable high-quality photo model: status, download/retry,
/// reveal in Finder, and delete.
@available(macOS 14.0, *)
private struct PhotoModelSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Section("Photo Model") {
            switch state.modelState {
            case .notDownloaded:
                HStack {
                    Text("Not downloaded").foregroundStyle(.secondary)
                    Spacer()
                    Button("Download") { state.downloadModelNow() }
                }
            case .downloading(let fraction):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading… \(Int(fraction * 100))%")
                    ProgressView(value: fraction)
                }
            case .ready:
                HStack {
                    Text(state.modelSizeText.map { "Downloaded · \($0)" } ?? "Downloaded")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { state.revealModelInFinder() }
                    Button("Delete") { state.deleteModel() }
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Download failed").foregroundStyle(.red)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { state.downloadModelNow() }
                }
            }
            Text("High-quality photo removal uses a ~233 MB model, downloaded on first use and cached. Slide mode doesn't need it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Notification preferences: master toggle, per-channel toggles, and sound selection.
@available(macOS 14.0, *)
private struct NotificationsSection: View {
    @EnvironmentObject var notify: NotificationSettings

    var body: some View {
        Section("Notifications") {
            Toggle("Notify when a conversion finishes", isOn: Binding(
                get: { notify.enabled },
                set: { on in
                    notify.enabled = on
                    if on { NotificationManager.shared.requestAuthorizationIfNeeded() }
                }
            ))

            ForEach(NotificationChannel.allCases, id: \.self) { channel in
                Toggle(channel.displayName, isOn: Binding(
                    get: { notify.channels[channel] ?? true },
                    set: { notify.channels[channel] = $0 }
                ))
                .disabled(!notify.enabled)
                .padding(.leading, 16)
            }

            SoundPicker()
                .disabled(!notify.enabled)
        }
    }
}

/// Sound selection: system default, none, a built-in system sound, or a custom local file.
@available(macOS 14.0, *)
private struct SoundPicker: View {
    @EnvironmentObject var notify: NotificationSettings

    /// Stable tags for the picker rows.
    private enum Selection: Hashable {
        case systemDefault, none, system(String), custom
    }

    private var selection: Binding<Selection> {
        Binding(
            get: {
                switch notify.sound {
                case .systemDefault: return .systemDefault
                case .none: return .none
                case .system(let name): return .system(name)
                case .custom: return .custom
                }
            },
            set: { newValue in
                switch newValue {
                case .systemDefault: notify.sound = .systemDefault
                case .none: notify.sound = .none
                case .system(let name): notify.sound = .system(name: name)
                case .custom: chooseCustomFile()
                }
            }
        )
    }

    var body: some View {
        Picker("Sound", selection: selection) {
            Text("System default").tag(Selection.systemDefault)
            Text("None").tag(Selection.none)
            Divider()
            ForEach(SoundStore.systemSoundNames(), id: \.self) { name in
                Text(name).tag(Selection.system(name))
            }
            Divider()
            Text(customLabel).tag(Selection.custom)
        }

        // Only offer a preview for sounds we can play on demand. The system default is played
        // by macOS when the banner appears and can't be triggered audibly on its own.
        switch notify.sound {
        case .system, .custom:
            Button("Preview sound") {
                NotificationManager.shared.previewSound(notify.sound)
            }
        case .systemDefault:
            Text("Plays your Mac's default notification sound.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .none:
            Text("No sound will play.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Menu row for the custom option, showing the imported file name when present.
    private var customLabel: String {
        if case .custom(let fileName) = notify.sound {
            // Strip the UUID prefix we add on import for a cleaner display.
            let display = fileName.split(separator: "-", maxSplits: 1).last.map(String.init) ?? fileName
            return "Custom: \(display)"
        }
        return "Custom file…"
    }

    private func chooseCustomFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let fileName = try? SoundStore.importCustomSound(from: url) {
            notify.sound = .custom(fileName: fileName)
        }
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
