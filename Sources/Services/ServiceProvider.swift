import AppKit

/// Backs the macOS **Services** entry ("Remove Background (Peelr)"). When the user selects an
/// image in any app and picks the service, macOS hands us a pasteboard; we replace its contents
/// with a transparent PNG. The method name maps to `NSMessage` in Info.plist.
@available(macOS 14.0, *)
final class ServiceProvider: NSObject {

    @MainActor
    @objc func removeBackgroundService(
        _ pboard: NSPasteboard,
        userData: String?,
        error errorPtr: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        guard let image = readImage(from: pboard) else {
            errorPtr?.pointee = "No image was provided to Peelr." as NSString
            return
        }
        do {
            let png = try BackgroundRemover.shared.processToPNG(image, settings: RemovalSettings())
            pboard.clearContents()
            pboard.setData(png, forType: .png)
            NotificationManager.shared.notifyConversionComplete(channel: .services)
        } catch {
            errorPtr?.pointee = "Peelr could not process the image." as NSString
        }
    }

    private func readImage(from pboard: NSPasteboard) -> NSImage? {
        if let images = pboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first {
            return first
        }
        // Handle file URLs (e.g. an image selected in Finder).
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where NSImage(contentsOf: url) != nil {
                return NSImage(contentsOf: url)
            }
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }
}
