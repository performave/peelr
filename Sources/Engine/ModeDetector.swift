import CoreGraphics
import simd

/// Decides slide vs photo for `RemovalMode.auto`.
///
/// Distinguishes *synthetic / flat-background* images (slides, screenshots, code, diagrams,
/// logos) from *photographs*, so `.auto` sends the former to the crisp color-key engine and the
/// latter to BiRefNet. The feature set follows the classical (non-ML) image-forensics literature
/// on natural-vs-synthetic classification; three signals, all from a single raster pass:
///
///   • **Palette richness** — count of distinct (coarsely quantized) colors. Synthetic images use
///     a small, discrete palette (cf. color-discreteness classifiers, USPTO 7,346,211).
///   • **Background coverage** — fraction of the frame near the border color. A slide/screenshot
///     has one flat background spanning most of the image; a photo does not.
///   • **Background noise** — spread of those near-background pixels. A camera sensor imprints
///     noise *everywhere*, even on a plain wall or sky, so a photo's background is never perfectly
///     flat; a rendered/screenshot background is noise-free (cf. sensor-pattern-noise forensics).
///     This is what keeps a plain-backdrop *photo* from being mistaken for a slide.
///
/// Relying on border-ring flatness alone (the old heuristic) failed on screenshots whose content
/// runs to the edges — e.g. a code screenshot — which then went to BiRefNet and came out ghosted.
enum ModeDetector {

    static func detect(_ image: CGImage) -> RemovalMode {
        guard let f = features(image) else { return .photo }
        let flatBackground = f.backgroundCoverage >= 0.30
        // Synthetic image ⇒ color-key: a dominant flat background that is either drawn from a
        // limited palette or carries no sensor noise (so it isn't a camera photo).
        if flatBackground && (f.distinctColors <= 900 || f.backgroundNoise < 1.5) { return .slide }
        // Fallback: a very clean, uniform border (classic slide with generous margins).
        if f.borderStd < 18 { return .slide }
        return .photo
    }

    private struct Features {
        var borderStd: Double
        var backgroundCoverage: Double
        var backgroundNoise: Double
        var distinctColors: Int
    }

    private static func features(_ image: CGImage) -> Features? {
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

        // --- Border ring: median (robust bg color) + std-dev (flatness). ---
        let band = max(1, min(width, height) / 25)
        var borderR: [UInt8] = [], borderG: [UInt8] = [], borderB: [UInt8] = []
        var sum = SIMD3<Double>(0, 0, 0)
        var sumSq = SIMD3<Double>(0, 0, 0)
        for y in 0..<height {
            let isTopBottom = y < band || y >= height - band
            for x in 0..<width where isTopBottom || x < band || x >= width - band {
                let o = (y * width + x) * 4
                let r = data[o], g = data[o + 1], b = data[o + 2]
                borderR.append(r); borderG.append(g); borderB.append(b)
                let c = SIMD3<Double>(Double(r), Double(g), Double(b))
                sum += c
                sumSq += c * c
            }
        }
        let n = Double(borderR.count)
        guard n > 0 else { return nil }
        let mean = sum / n
        let variance = (sumSq / n) - (mean * mean)
        let borderStd = (sqrt(max(0, variance.x)) + sqrt(max(0, variance.y)) + sqrt(max(0, variance.z))) / 3.0

        func median(_ v: inout [UInt8]) -> Double { v.sort(); return Double(v[v.count / 2]) }
        let bg = SIMD3<Double>(median(&borderR), median(&borderG), median(&borderB))

        // --- Whole-image scan (strided) for bg coverage + distinct colors. ---
        // Cap work at ~50k samples regardless of resolution.
        let total = width * height
        let stride = max(1, total / 50_000)
        let bgDistThreshold = 45.0    // RGB Euclidean distance treated as "same as background".
        var seen = [Bool](repeating: false, count: 4096)   // 4 bits/channel palette buckets.
        var nearBg = 0
        var nearBgSqSum = 0.0   // Σ squared distance of near-bg pixels from bg ⇒ background noise.
        var sampled = 0
        var i = 0
        while i < total {
            let o = i * 4
            let c = SIMD3<Double>(Double(data[o]), Double(data[o + 1]), Double(data[o + 2]))
            let d = c - bg
            let distSq = d.x * d.x + d.y * d.y + d.z * d.z
            if distSq < bgDistThreshold * bgDistThreshold {
                nearBg += 1
                nearBgSqSum += distSq
            }
            let bucket = (Int(data[o]) >> 4) << 8 | (Int(data[o + 1]) >> 4) << 4 | (Int(data[o + 2]) >> 4)
            seen[bucket] = true
            sampled += 1
            i += stride
        }

        return Features(
            borderStd: borderStd,
            backgroundCoverage: sampled > 0 ? Double(nearBg) / Double(sampled) : 0,
            // RMS per-channel spread of the background region (0 ⇒ perfectly flat / rendered).
            backgroundNoise: nearBg > 0 ? sqrt(nearBgSqSum / Double(nearBg) / 3.0) : 0,
            distinctColors: seen.lazy.filter { $0 }.count
        )
    }
}
