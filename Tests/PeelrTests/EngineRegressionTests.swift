import AppKit
import CoreGraphics
import CoreImage
import XCTest

final class EngineRegressionTests: XCTestCase {
    func testAutoModeDetectsFlatBorderAsSlide() throws {
        let image = try makeImage(width: 16, height: 16) { x, y in
            if (5...10).contains(x), (5...10).contains(y) {
                return (20, 20, 20, 255)
            }
            return (245, 245, 245, 255)
        }

        XCTAssertEqual(ModeDetector.detect(image), .slide)
    }

    func testAutoModeDetectsNoisyTexturedImageAsPhoto() throws {
        // A photograph: a rich palette with sensor-like per-pixel noise everywhere and no single
        // flat background color — the opposite of a rendered slide/screenshot.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> UInt8 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return UInt8(seed & 0xFF)
        }
        let image = try makeImage(width: 96, height: 96) { _, _ in
            (rand(), rand(), rand(), 255)
        }

        XCTAssertEqual(ModeDetector.detect(image), .photo)
    }

    func testAutoModeDetectsFlatBackgroundScreenshotAsSlide() throws {
        // A code screenshot: flat, noise-free background with hard-edged text-like marks that run
        // all the way to the borders. The old border-ring heuristic mislabeled this as a photo.
        let image = try makeImage(width: 96, height: 96) { x, y in
            let ink = (y % 12 < 3) && (x % 7 < 5)   // dense "text" rows reaching every edge
            return ink ? (40, 40, 60, 255) : (250, 250, 250, 255)
        }

        XCTAssertEqual(ModeDetector.detect(image), .slide)
    }

    func testColorKeyRemovesEnclosedBackgroundWhenInteriorProtectionIsDisabled() throws {
        let image = try makeCounterImage()
        let matte = try ColorKeyMatter().matte(
            image,
            settings: RemovalSettings(mode: .slide, tolerance: 18, feather: 0, protectInterior: false)
        )
        let mask = try rgbaPixels(from: matte, width: image.width, height: image.height)

        XCTAssertLessThan(mask.valueAt(x: 4, y: 4), 8, "The white counter inside the black glyph should be removed.")
        XCTAssertGreaterThan(mask.valueAt(x: 3, y: 4), 247, "The black glyph stroke should be kept.")
    }

    func testColorKeyKeepsEnclosedBackgroundWhenInteriorProtectionIsEnabled() throws {
        let image = try makeCounterImage()
        let matte = try ColorKeyMatter().matte(
            image,
            settings: RemovalSettings(mode: .slide, tolerance: 18, feather: 0, protectInterior: true)
        )
        let mask = try rgbaPixels(from: matte, width: image.width, height: image.height)

        XCTAssertGreaterThan(mask.valueAt(x: 4, y: 4), 247, "Interior protection should keep enclosed white content.")
        XCTAssertLessThan(mask.valueAt(x: 0, y: 0), 8, "Edge-connected background should still be removed.")
    }

    func testNSImageConversionPreservesBitmapPixelDimensions() throws {
        let image = try makeImage(width: 2, height: 2) { x, y in
            UInt8(x + y).isMultiple(of: 2) ? (255, 255, 255, 255) : (0, 0, 0, 255)
        }
        let rep = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(size: CGSize(width: 1, height: 1))
        nsImage.addRepresentation(rep)

        let converted = try XCTUnwrap(ImageCompositing.cgImage(from: nsImage))

        XCTAssertEqual(converted.width, 2)
        XCTAssertEqual(converted.height, 2)
    }

    private func makeCounterImage() throws -> CGImage {
        try makeImage(width: 9, height: 9) { x, y in
            let isStroke = ((3...5).contains(x) && (3...5).contains(y)) && !(x == 4 && y == 4)
            return isStroke ? (0, 0, 0, 255) : (255, 255, 255, 255)
        }
    }

    private func makeImage(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) throws -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let rgba = pixel(x, y)
                data[offset] = rgba.0
                data[offset + 1] = rgba.1
                data[offset + 2] = rgba.2
                data[offset + 3] = rgba.3
            }
        }

        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: ImageCompositing.srgb,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            throw TestError.imageCreationFailed
        }

        return image
    }

    private func rgbaPixels(from image: CIImage, width: Int, height: Int) throws -> MaskPixels {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        ImageCompositing.context.render(
            image,
            toBitmap: &data,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: ImageCompositing.srgb
        )
        return MaskPixels(width: width, data: data)
    }

    private struct MaskPixels {
        let width: Int
        let data: [UInt8]

        func valueAt(x: Int, y: Int) -> UInt8 {
            data[(y * width + x) * 4]
        }
    }

    private enum TestError: Error {
        case imageCreationFailed
    }
}
