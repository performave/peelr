import SwiftUI
import UniformTypeIdentifiers

@available(macOS 14.0, *)
struct MainWindow: View {
    @EnvironmentObject var state: AppState
    @State private var compareMode: CompareMode = .sideBySide
    @AppStorage("app.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        HSplitView {
            previews
                .frame(minWidth: 360)
            controls
                .frame(width: 260)
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
                    Label("From Clipboard", systemImage: "doc.on.clipboard")
                }
            }
        }
    }

    private var previews: some View {
        VStack(spacing: 8) {
            ComparisonView(original: state.sourceImage,
                           result: state.resultImage,
                           mode: $compareMode)
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
        .onChange(of: state.settings) { _, _ in
            state.reprocess()
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
