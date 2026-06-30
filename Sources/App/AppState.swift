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
    @Published var settings: RemovalSettings = .default
    @Published var isProcessing = false
    @Published var statusMessage: String = "Drop an image, or use the clipboard."
    @Published var lastResolvedMode: RemovalMode?

    private var resultPNG: Data?

    /// Load an image into the editor (from drop, file, or clipboard).
    func load(_ image: NSImage) {
        sourceImage = image
        resultImage = nil
        resultPNG = nil
        reprocess()
    }

    /// Re-run the engine with current settings (called on load and slider changes).
    func reprocess() {
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
                    self.isProcessing = false
                    let engine = out.usedBiRefNet ? "BiRefNet" : (out.resolvedMode == .slide ? "color-key" : "Vision")
                    self.statusMessage = "Done · \(out.resolvedMode.displayName) · \(engine)"
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.statusMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Process the current clipboard image in place. Used by hotkey, menu, and intent.
    @discardableResult
    func processClipboard() -> Bool {
        guard let image = PasteboardService.readImage() else {
            statusMessage = "No image on the clipboard."
            return false
        }
        do {
            let png = try BackgroundRemover.shared.processToPNG(image, settings: settings)
            PasteboardService.writePNG(png)
            statusMessage = "Clipboard background removed."
            // Mirror into the editor for visual confirmation.
            load(image)
            return true
        } catch {
            statusMessage = "Clipboard failed: \(error.localizedDescription)"
            return false
        }
    }

    func copyResult() {
        guard let resultPNG else { return }
        PasteboardService.writePNG(resultPNG)
        statusMessage = "Copied transparent PNG to clipboard."
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
