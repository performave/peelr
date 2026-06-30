import AppKit

/// Reads images from and writes transparent PNGs to the general pasteboard.
enum PasteboardService {

    /// Best available image on the clipboard, if any.
    static func readImage() -> NSImage? {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first {
            return first
        }
        // Fall back to raw data for slide apps that put PNG/TIFF on the board directly.
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pb.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    /// Replace the clipboard contents with a transparent PNG.
    static func writePNG(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }
}
