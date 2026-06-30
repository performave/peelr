import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import AppKit

/// Shared image conversion + compositing helpers used by every matting strategy.
enum ImageCompositing {

    static let context: CIContext = {
        // sRGB working space keeps results predictable across screens and PNG export.
        CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }()

    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: - Conversions

    static func ciImage(from cgImage: CGImage) -> CIImage {
        CIImage(cgImage: cgImage)
    }

    static func cgImage(from ciImage: CIImage) -> CGImage? {
        let rect = ciImage.extent.isInfinite
            ? CGRect(x: 0, y: 0, width: 1, height: 1)
            : ciImage.extent
        return context.createCGImage(ciImage, from: rect, format: .RGBA8, colorSpace: srgb)
    }

    static func cgImage(from nsImage: NSImage) -> CGImage? {
        // Prefer the highest-resolution bitmap representation. `nsImage.size` is in points,
        // so a Retina screenshot (e.g. a lecture slide) would otherwise be processed at half
        // its pixel resolution. Pick the rep with the most actual pixels instead.
        let bestRep = nsImage.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        if let cg = bestRep?.cgImage {
            return cg
        }
        // Fallback: rasterize at full pixel dimensions if we can determine them.
        let pixelW = nsImage.representations.map(\.pixelsWide).max() ?? Int(nsImage.size.width)
        let pixelH = nsImage.representations.map(\.pixelsHigh).max() ?? Int(nsImage.size.height)
        var rect = CGRect(x: 0, y: 0, width: pixelW, height: pixelH)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: - Mask application

    /// Applies a single-channel (grayscale) mask as the alpha of `source`.
    /// White in the mask = keep (opaque), black = remove (transparent).
    static func apply(mask: CIImage, to source: CIImage, feather: CGFloat = 0) -> CIImage {
        var maskImage = mask.cropped(to: source.extent)
        if feather > 0 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = maskImage
            blur.radius = Float(feather)
            maskImage = (blur.outputImage ?? maskImage).cropped(to: source.extent)
        }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
        blend.backgroundImage = CIImage(color: .clear).cropped(to: source.extent)
        blend.maskImage = maskImage
        return (blend.outputImage ?? source).cropped(to: source.extent)
    }

    // MARK: - PNG encoding

    static func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = CGSize(width: cgImage.width, height: cgImage.height)
        return rep.representation(using: .png, properties: [:])
    }

    static func nsImage(from cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }
}
