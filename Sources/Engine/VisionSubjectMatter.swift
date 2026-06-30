import Vision
import CoreImage
import CoreGraphics

/// Photo fallback using Apple's built-in foreground-instance mask. Used when the bundled
/// BiRefNet Core ML model is unavailable. Same model family as the macOS "Remove Background".
@available(macOS 14.0, *)
struct VisionSubjectMatter: Matter {

    enum VisionError: Error { case noForeground }

    func matte(_ source: CGImage, settings: RemovalSettings) throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: source, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else { throw VisionError.noForeground }
        let pixelBuffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances, from: handler
        )
        return CIImage(cvPixelBuffer: pixelBuffer)
    }
}
