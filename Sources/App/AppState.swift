import SwiftUI
import AppKit

/// Shared observable state for the window UI and menu bar.
@available(macOS 14.0, *)
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    init() {
        AppState.sharedForHotKey = self
    }

    @Published var sourceImage: NSImage?
    @Published var resultImage: NSImage?
    /// Persisted so the hotkey, menu bar, and clipboard action reuse the same config
    /// across launches. Saved on every change.
    @Published var settings: RemovalSettings = RemovalSettingsStore.load() {
        didSet { RemovalSettingsStore.save(settings) }
    }
    @Published var isProcessing = false
    @Published var statusMessage: String = "Drop an image, or use the clipboard."
    @Published var lastResolvedMode: RemovalMode?
    /// Engine that produced the current result (e.g. "BiRefNet", "Color-key", "Vision").
    @Published var lastEngine: String?

    /// The bottom status bar's cells, shown left→right divided by vertical rules. The transient
    /// state message always leads; the mode/engine/size cells persist while a result is loaded.
    var statusSegments: [String] {
        var segments = [statusMessage]
        if sourceImage != nil {
            if let mode = lastResolvedMode { segments.append(mode.displayName) }
            if let engine = lastEngine { segments.append(engine) }
            if let size = sourceDimensionText { segments.append(size) }
        }
        return segments
    }

    /// Pixel dimensions of the loaded source image (highest-resolution representation).
    private var sourceDimensionText: String? {
        guard let rep = sourceImage?.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh })
        else { return nil }
        return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
    }

    /// Incremented to request that the main window re-show the onboarding sheet.
    @Published var onboardingRequestID = 0

    /// Lifecycle of the downloadable high-quality photo model, surfaced in Settings.
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }
    @Published var modelState: ModelState =
        ModelStore.shared.readyModelURL != nil ? .ready : .notDownloaded

    /// Progress surfaced on the Result pane: the model download reports a real fraction; an
    /// inference pass is indeterminate (the bar trickles). See `TrickleProgressBar`.
    var workProgress: WorkProgress {
        if case .downloading(let fraction) = modelState {
            return WorkProgress(active: true, fraction: fraction)
        }
        return WorkProgress(active: isProcessing, fraction: nil)
    }

    private var resultPNG: Data?

    /// Guards against kicking off more than one model download at a time.
    private var isFetchingModel = false

    /// Ask the main window to present the onboarding tour (from the menu bar).
    func showOnboarding() {
        onboardingRequestID += 1
    }

    /// Load an image into the editor (from drop, file, or clipboard).
    func load(_ image: NSImage) {
        sourceImage = image
        resultImage = nil
        resultPNG = nil
        reprocess()
    }

    /// Re-run the engine with current settings (called on load and slider changes).
    ///
    /// The heavy inference runs off the main actor via `Task.detached`, so the UI stays
    /// responsive. Pass `copyToPasteboard`/`channel` for the clipboard path so the result
    /// is written back and a completion notification is posted when inference finishes.
    func reprocess(copyToPasteboard: Bool = false, channel: NotificationChannel? = nil) {
        guard let source = sourceImage,
              let cg = ImageCompositing.cgImage(from: source) else { return }
        let settings = self.settings
        isProcessing = true
        statusMessage = "Processing…"
        Task.detached(priority: .userInitiated) {
            do {
                let out = try BackgroundRemover.shared.process(cg, settings: settings)
                let png = ImageCompositing.pngData(from: out.image)
                let nsImage = ImageCompositing.nsImage(from: out.image)
                await MainActor.run {
                    self.resultImage = nsImage
                    self.resultPNG = png
                    self.lastResolvedMode = out.resolvedMode
                    self.lastEngine = out.usedBiRefNet
                        ? "BiRefNet"
                        : (out.resolvedMode == .slide ? "Color-key" : "Vision")
                    self.isProcessing = false
                    if copyToPasteboard, let png {
                        PasteboardService.writePNG(png)
                        if let channel {
                            NotificationManager.shared.notifyConversionComplete(channel: channel)
                        }
                        self.statusMessage = "Copied to clipboard"
                    } else {
                        self.statusMessage = "Done"
                    }
                    // Photo mode fell back to Vision because the high-quality model isn't
                    // downloaded yet. Fetch it now (once); reprocess when it's ready.
                    if out.resolvedMode == .photo && !out.usedBiRefNet {
                        self.ensureModelReady()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.statusMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Download + compile the high-quality photo model once, then reprocess so the current
    /// image upgrades from the Vision fallback to BiRefNet. No-op if already present/in-flight.
    func ensureModelReady() {
        guard ModelStore.shared.readyModelURL == nil, !isFetchingModel else { return }
        isFetchingModel = true
        modelState = .downloading(0)
        Task {
            defer { isFetchingModel = false }
            do {
                try await ModelStore.shared.ensureAvailable { fraction in
                    Task { @MainActor in
                        self.modelState = .downloading(fraction)
                        self.statusMessage = "Downloading photo model… \(Int(fraction * 100))%"
                    }
                }
                modelState = .ready
                statusMessage = "Photo model ready"
                if sourceImage != nil { reprocess() }
            } catch {
                modelState = .failed(error.localizedDescription)
                statusMessage = "Photo model unavailable: \(error.localizedDescription)"
            }
        }
    }

    /// Decide whether a settings change actually alters the current result before paying for a
    /// full reprocess. Tolerance and "protect interior" only affect the slide (color-key)
    /// engine, so in photo/vision modes changing them would just re-run BiRefNet to produce an
    /// identical image (the flicker users see when dragging those sliders). Mode and edge feather
    /// affect every mode's output, so they always reprocess.
    func settingsChanged(from old: RemovalSettings) {
        let new = settings
        guard new != old else { return }
        if new.mode != old.mode || new.feather != old.feather {
            reprocess()
            return
        }
        let slideOnlyChanged = new.tolerance != old.tolerance
            || new.protectInterior != old.protectInterior
        let resolved = new.mode == .auto ? lastResolvedMode : new.mode
        if slideOnlyChanged && resolved == .slide {
            reprocess()
        }
    }

    /// User-initiated download or retry from Settings (works with no image loaded).
    func downloadModelNow() { ensureModelReady() }

    /// Delete the cached model and release it from memory.
    func deleteModel() {
        do {
            try ModelStore.shared.deleteCache()
            BackgroundRemover.shared.unloadPhotoModel()
            modelState = .notDownloaded
            statusMessage = "Photo model deleted"
        } catch {
            statusMessage = "Couldn't delete model: \(error.localizedDescription)"
        }
    }

    /// Reveal the cached model (or its folder) in Finder.
    func revealModelInFinder() {
        let store = ModelStore.shared
        if let url = store.readyModelURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(
                at: store.modelsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(store.modelsDirectory)
        }
    }

    /// Human-readable size of the cached model, if present (for Settings).
    var modelSizeText: String? {
        ModelStore.shared.cachedByteCount.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
    }

    /// Process the current clipboard image in place. Used by hotkey, menu, and window button.
    /// Pass a `channel` to post a completion notification (nil for the in-window button).
    ///
    /// Inference runs off the main actor (see `reprocess`), so the UI never freezes. The
    /// clipboard is overwritten and the editor is updated when processing finishes. The
    /// return value only reports whether an image was found on the clipboard to start.
    @discardableResult
    func processClipboard(channel: NotificationChannel? = nil) -> Bool {
        guard let image = PasteboardService.readImage() else {
            statusMessage = "No image on the clipboard"
            return false
        }
        // Mirror into the editor and run a single inference that also writes the result back
        // to the clipboard on completion (avoids a redundant second pass).
        sourceImage = image
        resultImage = nil
        resultPNG = nil
        reprocess(copyToPasteboard: true, channel: channel)
        return true
    }

    func copyResult() {
        guard let resultPNG else { return }
        PasteboardService.writePNG(resultPNG)
        statusMessage = "Copied transparent PNG to clipboard"
    }

    func saveResult() {
        guard let resultPNG else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "no-background.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? resultPNG.write(to: url)
            statusMessage = "Saved to \(url.lastPathComponent)."
        }
    }
}
