import AppIntents
import AppKit
import UniformTypeIdentifiers

/// Shortcuts action: image in → transparent PNG out.
@available(macOS 14.0, *)
struct RemoveBackgroundIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove Background"
    static var description = IntentDescription(
        "Removes the background from an image. Auto-detects slides vs. photos."
    )

    @Parameter(title: "Image", supportedTypeIdentifiers: ["public.image"])
    var image: IntentFile

    @Parameter(title: "Mode", default: .auto)
    var mode: RemovalModeAppEnum

    @Parameter(title: "Tolerance", default: 18, controlStyle: .field,
               inclusiveRange: (1, 100))
    var tolerance: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Remove background from \(\.$image)") {
            \.$mode
            \.$tolerance
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let nsImage = NSImage(data: image.data) else {
            throw RemoveBackgroundError.invalidImage
        }
        var settings = RemovalSettings()
        settings.mode = mode.removalMode
        settings.tolerance = tolerance
        let png = try BackgroundRemover.shared.processToPNG(nsImage, settings: settings)
        let name = (image.filename as NSString?)?.deletingPathExtension ?? "image"
        let file = IntentFile(data: png, filename: "\(name)-nobg.png", type: .png)
        return .result(value: file)
    }
}

/// Shortcuts action: process whatever image is on the clipboard, in place.
@available(macOS 14.0, *)
struct RemoveBackgroundFromClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove Background from Clipboard"
    static var description = IntentDescription(
        "Reads the image on the clipboard, removes its background, and copies the result back."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let nsImage = PasteboardService.readImage() else {
            throw RemoveBackgroundError.noClipboardImage
        }
        let png = try BackgroundRemover.shared.processToPNG(nsImage, settings: RemovalSettings())
        PasteboardService.writePNG(png)
        return .result()
    }
}

enum RemoveBackgroundError: Error, CustomLocalizedStringResourceConvertible {
    case invalidImage
    case noClipboardImage

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidImage: return "The provided file is not a readable image."
        case .noClipboardImage: return "There is no image on the clipboard."
        }
    }
}

@available(macOS 14.0, *)
enum RemovalModeAppEnum: String, AppEnum {
    case auto, slide, photo

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Removal Mode"
    static var caseDisplayRepresentations: [RemovalModeAppEnum: DisplayRepresentation] = [
        .auto: "Auto",
        .slide: "Slide (flat background)",
        .photo: "Photo (subject)"
    ]

    var removalMode: RemovalMode {
        switch self {
        case .auto: return .auto
        case .slide: return .slide
        case .photo: return .photo
        }
    }
}
