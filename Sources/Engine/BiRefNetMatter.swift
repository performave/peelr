import CoreML
import CoreImage
import CoreGraphics
import Accelerate

/// High-quality photo engine backed by the BiRefNet/RMBG-2 Core ML model.
///
/// The model is downloaded and cached on demand by `ModelStore`; until it's ready,
/// `isAvailable` is false and `BackgroundRemover` falls back to `VisionSubjectMatter`.
/// The model is loaded lazily the first time it appears on disk.
///
/// The model takes a normalized `[1,3,1024,1024]` RGB tensor (ImageNet mean/std) and
/// emits single-channel mattes; `output_3` is the full-resolution `[1,1,1024,1024]` mask.
@available(macOS 14.0, *)
final class BiRefNetMatter: Matter {

    enum BiRefNetError: LocalizedError {
        case modelUnavailable, noMask
        var errorDescription: String? {
            switch self {
            case .modelUnavailable:
                return "The BiRefNet model isn't bundled. Reinstall the app or rebuild with the model."
            case .noMask:
                return "The BiRefNet model didn't return a matte for this image."
            }
        }
    }

    private static let side = 1024
    private static let inputName = "input"
    private static let outputName = "output_3"
    private static let mean: [Float] = [0.485, 0.456, 0.406]
    private static let std: [Float] = [0.229, 0.224, 0.225]

    private var model: MLModel?

    /// True once the cached model has been downloaded and can be loaded. Loads it lazily on
    /// first success so a download completing mid-session is picked up without a restart.
    var isAvailable: Bool { currentModel() != nil }

    private func currentModel() -> MLModel? {
        if let model { return model }
        guard let url = ModelStore.shared.readyModelURL else { return nil }
        let config = MLModelConfiguration()
        // Avoid the Neural Engine: compiling this int8 model for ANE stalls for minutes.
        // CPU+GPU loads in seconds and runs a warm matte in ~0.8s (see AGENTS.md notes).
        config.computeUnits = .cpuAndGPU
        model = try? MLModel(contentsOf: url, configuration: config)
        return model
    }

    /// Drop the loaded model so a deleted cache actually releases memory; it reloads lazily
    /// if the model is downloaded again.
    func unload() { model = nil }

    func matte(_ source: CGImage, settings: RemovalSettings) throws -> CIImage {
        guard let model = currentModel() else { throw BiRefNetError.modelUnavailable }

        let input = try makeInput(from: source)
        let provider = try MLDictionaryFeatureProvider(dictionary: [Self.inputName: input])
        let result = try model.prediction(from: provider)

        guard let matte = result.featureValue(for: Self.outputName)?.multiArrayValue,
              let maskImage = Self.maskImage(from: matte) else {
            throw BiRefNetError.noMask
        }
        return scale(CIImage(cgImage: maskImage), to: source)
    }

    /// Resize the source to 1024×1024 RGB and pack it into an ImageNet-normalized NCHW tensor.
    private func makeInput(from source: CGImage) throws -> MLMultiArray {
        let side = Self.side
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &rgba, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: ImageCompositing.srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw BiRefNetError.noMask }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))

        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)],
                                     dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        let plane = side * side
        for c in 0..<3 {
            let mean = Self.mean[c], invStd = 1 / Self.std[c]
            let base = c * plane
            for p in 0..<plane {
                let v = Float(rgba[p * 4 + c]) / 255.0
                ptr[base + p] = (v - mean) * invStd
            }
        }
        return array
    }

    /// Turn the model's `[1,1,H,W]` matte into an 8-bit grayscale CGImage.
    private static func maskImage(from matte: MLMultiArray) -> CGImage? {
        let dims = matte.shape.map(\.intValue)
        guard dims.count >= 2 else { return nil }
        let h = dims[dims.count - 2], w = dims[dims.count - 1]
        let count = h * w
        guard matte.count >= count else { return nil }

        // The mask is contiguous in the trailing H×W plane regardless of leading 1-dims.
        let offset = matte.count - count
        var floats = [Float](repeating: 0, count: count)
        switch matte.dataType {
        case .float32:
            let src = matte.dataPointer.bindMemory(to: Float.self, capacity: matte.count)
            floats.withUnsafeMutableBufferPointer { $0.baseAddress?.update(from: src.advanced(by: offset), count: count) }
        case .float16:
            let src16 = matte.dataPointer.bindMemory(to: UInt16.self, capacity: matte.count).advanced(by: offset)
            let ok = floats.withUnsafeMutableBufferPointer { dst -> Bool in
                var srcBuf = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src16),
                                           height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
                var dstBuf = vImage_Buffer(data: dst.baseAddress,
                                           height: 1, width: vImagePixelCount(count), rowBytes: count * 4)
                return vImageConvert_Planar16FtoPlanarF(&srcBuf, &dstBuf, 0) == kvImageNoError
            }
            guard ok else { return nil }
        default:
            for i in 0..<count { floats[i] = matte[offset + i].floatValue }
        }
        // `output_3` is raw logits: map to alpha with sigmoid (255 / (1 + e^-x)), then clamp.
        var n = Int32(count)
        vDSP_vneg(floats, 1, &floats, 1, vDSP_Length(count))          // -x
        vvexpf(&floats, floats, &n)                                   // e^-x
        var one: Float = 1
        vDSP_vsadd(floats, 1, &one, &floats, 1, vDSP_Length(count))   // 1 + e^-x
        var scale: Float = 255.0
        vDSP_svdiv(&scale, floats, 1, &floats, 1, vDSP_Length(count)) // 255 / (1 + e^-x)
        var lo: Float = 0, hi: Float = 255
        vDSP_vclip(floats, 1, &lo, &hi, &floats, 1, vDSP_Length(count))

        var bytes = [UInt8](repeating: 0, count: count)
        vDSP_vfixu8(floats, 1, &bytes, 1, vDSP_Length(count))

        return bytes.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
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
