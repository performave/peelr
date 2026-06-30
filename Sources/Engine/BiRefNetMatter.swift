import Vision
import CoreML
import CoreImage
import CoreGraphics

/// High-quality photo engine backed by a bundled BiRefNet Core ML model.
///
/// The model is optional: `isAvailable` is false when `BiRefNet.mlpackage` was not bundled,
/// letting `BackgroundRemover` fall back to `VisionSubjectMatter`.
@available(macOS 14.0, *)
final class BiRefNetMatter: Matter {

    enum BiRefNetError: Error { case modelUnavailable, noMask }

    private let visionModel: VNCoreMLModel?

    init() {
        self.visionModel = Self.loadModel()
    }

    var isAvailable: Bool { visionModel != nil }

    private static func loadModel() -> VNCoreMLModel? {
        // Accept either a compiled .mlmodelc or a source .mlpackage in the app bundle.
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "BiRefNet", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "BiRefNet", withExtension: "mlpackage")
        ]
        let config = MLModelConfiguration()
        config.computeUnits = .all
        for case let url? in candidates {
            do {
                let compiled = url.pathExtension == "mlmodelc"
                    ? url
                    : try MLModel.compileModel(at: url)
                let mlModel = try MLModel(contentsOf: compiled, configuration: config)
                return try VNCoreMLModel(for: mlModel)
            } catch {
                continue
            }
        }
        return nil
    }

    func matte(_ source: CGImage, settings: RemovalSettings) throws -> CIImage {
        guard let visionModel else { throw BiRefNetError.modelUnavailable }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: source, options: [:])
        try handler.perform([request])

        // BiRefNet emits a single-channel matte; accept pixel-buffer or feature outputs.
        if let pixelObs = request.results?.first as? VNPixelBufferObservation {
            let mask = CIImage(cvPixelBuffer: pixelObs.pixelBuffer)
            return scale(mask, to: source)
        }
        throw BiRefNetError.noMask
    }

    /// Stretch the model's fixed-size matte back over the source extent.
    private func scale(_ mask: CIImage, to source: CGImage) -> CIImage {
        let target = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let sx = target.width / mask.extent.width
        let sy = target.height / mask.extent.height
        return mask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .cropped(to: target)
    }
}
