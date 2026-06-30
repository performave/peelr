import CoreGraphics
import simd

/// Decides slide vs photo for `RemovalMode.auto`.
///
/// Heuristic: sample the border ring. A slide has a tight, near-uniform border color
/// (low variance); a photo's border is busy (high variance).
enum ModeDetector {

    static func detect(_ image: CGImage) -> RemovalMode {
        guard let stats = borderColorVariance(image) else { return .photo }
        // Empirically: flat slide backgrounds sit well under this RGB std-dev threshold.
        return stats < 18.0 ? .slide : .photo
    }

    /// Average per-channel standard deviation (0–255) of the outer border ring.
    private static func borderColorVariance(_ image: CGImage) -> Double? {
        let width = image.width, height = image.height
        guard width > 4, height > 4 else { return nil }

        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let band = max(1, min(width, height) / 25)
        var sum = SIMD3<Double>(0, 0, 0)
        var sumSq = SIMD3<Double>(0, 0, 0)
        var n = 0
        for y in 0..<height {
            let isTopBottom = y < band || y >= height - band
            for x in 0..<width where isTopBottom || x < band || x >= width - band {
                let o = (y * width + x) * 4
                let c = SIMD3<Double>(Double(data[o]), Double(data[o + 1]), Double(data[o + 2]))
                sum += c
                sumSq += c * c
                n += 1
            }
        }
        guard n > 0 else { return nil }
        let mean = sum / Double(n)
        let variance = (sumSq / Double(n)) - (mean * mean)
        let std = SIMD3<Double>(sqrt(max(0, variance.x)), sqrt(max(0, variance.y)), sqrt(max(0, variance.z)))
        return (std.x + std.y + std.z) / 3.0
    }
}
