import CoreImage
import CoreGraphics
import AppKit

/// Orchestrates mode detection, strategy selection, and final RGBA composition.
@available(macOS 14.0, *)
final class BackgroundRemover {

    static let shared = BackgroundRemover()

    private let colorKey = ColorKeyMatter()
    private let biRefNet = BiRefNetMatter()
    private let vision = VisionSubjectMatter()

    struct Output {
        let image: CGImage
        let resolvedMode: RemovalMode
        let usedBiRefNet: Bool
    }

    /// Process a CGImage and return a transparent-background result.
    func process(_ source: CGImage, settings: RemovalSettings) throws -> Output {
        let resolved: RemovalMode = settings.mode == .auto
            ? ModeDetector.detect(source)
            : settings.mode

        var usedBiRefNet = false
        let mask: CIImage

        switch resolved {
        case .slide:
            mask = try colorKey.matte(source, settings: settings)
        case .photo, .auto:
            if biRefNet.isAvailable {
                mask = try biRefNet.matte(source, settings: settings)
                usedBiRefNet = true
            } else {
                mask = try vision.matte(source, settings: settings)
            }
        }

        let src = ImageCompositing.ciImage(from: source)
        let composed = ImageCompositing.apply(mask: mask, to: src, feather: CGFloat(settings.feather))
        guard let cg = ImageCompositing.cgImage(from: composed) else {
            throw RemoverError.compositionFailed
        }
        return Output(image: cg, resolvedMode: resolved, usedBiRefNet: usedBiRefNet)
    }

    /// Convenience for clipboard/intents: NSImage in, transparent PNG data out.
    func processToPNG(_ nsImage: NSImage, settings: RemovalSettings) throws -> Data {
        guard let cg = ImageCompositing.cgImage(from: nsImage) else {
            throw RemoverError.invalidImage
        }
        let out = try process(cg, settings: settings)
        guard let png = ImageCompositing.pngData(from: out.image) else {
            throw RemoverError.compositionFailed
        }
        return png
    }

    enum RemoverError: Error { case invalidImage, compositionFailed }
}
