import CoreImage
import CoreGraphics

/// The user-facing processing mode.
enum RemovalMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case slide
    case photo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .slide: return "Slide"
        case .photo: return "Photo"
        }
    }
}

/// Tunable parameters surfaced in the UI and used by the engine.
struct RemovalSettings: Sendable, Equatable {
    var mode: RemovalMode = .auto
    /// Color-key tolerance (CIELAB ΔE band half-width). Larger removes more.
    var tolerance: Double = 18
    /// Edge feather radius in pixels.
    var feather: Double = 1.0
    /// When true, color-key only removes background contiguous with the image edges
    /// (flood-fill). When false (default), removes the bg color everywhere — this is
    /// what makes the inside of letters like O/a/e transparent.
    var protectInterior: Bool = false

    static let `default` = RemovalSettings()
}

/// A strategy that produces a grayscale alpha mask for a source image.
/// White = keep (foreground), black = remove (background).
protocol Matter {
    func matte(_ source: CGImage, settings: RemovalSettings) throws -> CIImage
}
