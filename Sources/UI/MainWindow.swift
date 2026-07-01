import SwiftUI
import UniformTypeIdentifiers

@available(macOS 14.0, *)
struct MainWindow: View {
    @EnvironmentObject var state: AppState
    @State private var compareMode: CompareMode = .sideBySide
    @AppStorage("app.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                previews
                    .frame(minWidth: 360)
                controls
                    .frame(width: 260)
            }
            StatusBar(segments: state.statusSegments)
        }
        .frame(minWidth: 720, minHeight: 460)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            if !hasSeenOnboarding { showOnboarding = true }
        }
        .onChange(of: state.onboardingRequestID) { _, _ in
            showOnboarding = true
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Compare", selection: $compareMode) {
                    ForEach(CompareMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.processClipboard()
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                .labelStyle(.titleAndIcon)
                .help("Remove the background from the image currently on your clipboard, then copy the transparent result back to the clipboard.")
            }
        }
    }

    private var previews: some View {
        ComparisonView(original: state.sourceImage,
                       result: state.resultImage,
                       mode: $compareMode,
                       progress: state.workProgress)
            .padding(12)
            .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: handleDrop)
    }

    private var controls: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $state.settings.mode) {
                    ForEach(RemovalMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let resolved = state.lastResolvedMode, state.settings.mode == .auto {
                    Text("Auto chose: \(resolved.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Color key (slides)") {
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
            }

            Section {
                Button("Re-process") { state.reprocess() }
                    .disabled(state.sourceImage == nil)
                Button("Copy result") { state.copyResult() }
                    .disabled(state.resultImage == nil)
                Button("Save PNG…") { state.saveResult() }
                    .disabled(state.resultImage == nil)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, -8)
        .onChange(of: state.settings) { old, _ in
            state.settingsChanged(from: old)
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                if let image = object as? NSImage {
                    DispatchQueue.main.async { state.load(image) }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async { state.load(image) }
            }
            return true
        }
        return false
    }
}

/// A slim status bar along the bottom edge of the window (à la Finder/Xcode). Shows discrete
/// fields — state, mode, engine, image size — in their own cells divided by vertical rules,
/// rather than one dot-joined string. Keeps transient state out of the preview area.
@available(macOS 14.0, *)
private struct StatusBar: View {
    let segments: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Divider().frame(height: 11)
                }
                Text(segment)
                    .font(.caption)
                    // The leading cell (transient state) reads a touch stronger than the
                    // persistent metadata cells that follow it.
                    .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
        .animation(.default, value: segments)
    }
}
