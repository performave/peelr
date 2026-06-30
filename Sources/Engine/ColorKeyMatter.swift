import CoreImage
import CoreGraphics
import simd

/// Slide / flat-background engine.
///
/// Estimates the background color from the image border, then builds an alpha mask by
/// perceptual (CIELAB ΔE) distance to that color. Removal is global by default, so the
/// enclosed counters of letters (inside O, a, e, P, …) become transparent too — the thing
/// the macOS built-in and naive flood-fill both get wrong.
struct ColorKeyMatter: Matter {

    enum ColorKeyError: Error { case rasterizationFailed }

    func matte(_ source: CGImage, settings: RemovalSettings) throws -> CIImage {
        let width = source.width
        let height = source.height
        guard let pixels = rasterize(source) else { throw ColorKeyError.rasterizationFailed }

        let labBuffer = makeLabBuffer(pixels: pixels, width: width, height: height)
        let bg = estimateBackgroundLab(labBuffer, width: width, height: height)

        let tol = max(1.0, settings.tolerance)
        let half = max(2.0, tol * 0.5)

        // removal[i] in [0,1]: 1 = fully background (transparent), 0 = keep.
        let lower: Double = tol - half
        let span: Double = 2 * half
        var removal = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let d: Double = deltaE(labBuffer[i], bg)
            var r: Double = 1.0 - ((d - lower) / span)
            r = min(1.0, max(0.0, r))
            removal[i] = Float(r)
        }

        if settings.protectInterior {
            restrictToEdgeConnected(&removal, width: width, height: height)
        }

        // alpha = 255 * (1 - removal)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            alpha[i] = UInt8((1.0 - removal[i]) * 255.0)
        }

        guard let maskCG = makeGrayImage(alpha, width: width, height: height) else {
            throw ColorKeyError.rasterizationFailed
        }
        return CIImage(cgImage: maskCG)
    }

    // MARK: - Rasterization

    /// Returns RGBA8 bytes (premultipliedLast) for the image.
    private func rasterize(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &data,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: ImageCompositing.srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    // MARK: - Color science

    private func makeLabBuffer(pixels: [UInt8], width: Int, height: Int) -> [SIMD3<Float>] {
        var lab = [SIMD3<Float>](repeating: .zero, count: width * height)
        for i in 0..<(width * height) {
            let o = i * 4
            lab[i] = rgbToLab(r: pixels[o], g: pixels[o + 1], b: pixels[o + 2])
        }
        return lab
    }

    private func rgbToLab(r: UInt8, g: UInt8, b: UInt8) -> SIMD3<Float> {
        func lin(_ c: Float) -> Float {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = lin(Float(r) / 255), gl = lin(Float(g) / 255), bl = lin(Float(b) / 255)
        // sRGB -> XYZ (D65)
        let x = rl * 0.4124 + gl * 0.3576 + bl * 0.1805
        let y = rl * 0.2126 + gl * 0.7152 + bl * 0.0722
        let z = rl * 0.0193 + gl * 0.1192 + bl * 0.9505
        // Normalize by D65 white.
        let xn: Float = 0.95047, yn: Float = 1.0, zn: Float = 1.08883
        func f(_ t: Float) -> Float {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
        }
        let fx = f(x / xn), fy = f(y / yn), fz = f(z / zn)
        return SIMD3<Float>(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private func deltaE(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Double {
        let d = a - b
        return Double(sqrt(d.x * d.x + d.y * d.y + d.z * d.z))
    }

    /// Median Lab of the border ring (outer ~4% frame).
    private func estimateBackgroundLab(_ lab: [SIMD3<Float>], width: Int, height: Int) -> SIMD3<Float> {
        let band = max(1, min(width, height) / 25)
        var samples: [SIMD3<Float>] = []
        samples.reserveCapacity((width + height) * band * 2)
        for y in 0..<height {
            let isTopBottom = y < band || y >= height - band
            for x in 0..<width {
                if isTopBottom || x < band || x >= width - band {
                    samples.append(lab[y * width + x])
                }
            }
        }
        guard !samples.isEmpty else { return .zero }
        // Per-channel median is robust to a few foreground pixels touching the edge.
        func median(_ vals: [Float]) -> Float {
            let s = vals.sorted()
            return s[s.count / 2]
        }
        return SIMD3<Float>(
            median(samples.map { $0.x }),
            median(samples.map { $0.y }),
            median(samples.map { $0.z })
        )
    }

    // MARK: - Edge-connected restriction (optional flood fill)

    private func restrictToEdgeConnected(_ removal: inout [Float], width: Int, height: Int) {
        let count = width * height
        var connected = [Bool](repeating: false, count: count)
        var stack: [Int] = []

        func consider(_ idx: Int) {
            if removal[idx] > 0.5 && !connected[idx] {
                connected[idx] = true
                stack.append(idx)
            }
        }
        for x in 0..<width { consider(x); consider((height - 1) * width + x) }
        for y in 0..<height { consider(y * width); consider(y * width + width - 1) }

        while let idx = stack.popLast() {
            let x = idx % width, y = idx / width
            if x > 0 { consider(idx - 1) }
            if x < width - 1 { consider(idx + 1) }
            if y > 0 { consider(idx - width) }
            if y < height - 1 { consider(idx + width) }
        }
        for i in 0..<count where !connected[i] { removal[i] = 0 }
    }

    // MARK: - Mask image

    private func makeGrayImage(_ alpha: [UInt8], width: Int, height: Int) -> CGImage? {
        var buffer = alpha
        guard let provider = CGDataProvider(data: Data(bytes: &buffer, count: buffer.count) as CFData) else {
            return nil
        }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
