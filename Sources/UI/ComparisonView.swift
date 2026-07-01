import SwiftUI

enum CompareMode: String, CaseIterable, Identifiable {
    case sideBySide
    case reveal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sideBySide: return "Side by Side"
        case .reveal: return "Reveal (hover)"
        }
    }
}

/// Before/after viewer with shared zoom + pan.
///
/// The mode Picker lives here; the zoom/pan/reveal state lives in `ComparisonCanvas` so that the
/// constant transform updates during panning/hovering don't re-render (and drop clicks on) the
/// segmented control.
struct ComparisonView: View {
    let original: NSImage?
    let result: NSImage?
    @Binding var mode: CompareMode

    var body: some View {
        // The mode Picker lives in the window toolbar (see MainWindow) so the preview's
        // high-frequency hover/pan updates can never starve its clicks.
        ComparisonCanvas(original: original, result: result, mode: mode)
    }
}

/// Owns the transform state and renders the panes. Isolated so its frequent updates stay local.
private struct ComparisonCanvas: View {
    let original: NSImage?
    let result: NSImage?
    let mode: CompareMode

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var revealFraction: CGFloat = 0.5

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 12

    var body: some View {
        VStack(spacing: 8) {
            content
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            zoomControls
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .sideBySide:
            HStack(spacing: 6) {
                pane(title: "Original", image: original, placeholder: "Drop image here")
                pane(title: "Result", image: result, placeholder: "—")
            }
        case .reveal:
            revealPane
        }
    }

    private func pane(title: String, image: NSImage?, placeholder: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            layer(image: image, placeholder: placeholder)
                .overlay(gestureCapture(hoverEnabled: false))
        }
    }

    private var revealPane: some View {
        GeometryReader { geo in
            ZStack {
                // Before (original) on the left side of the curtain.
                layer(image: original, placeholder: "Drop image here")
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * revealFraction)
                    }
                // After (result, over its own checkerboard) on the right.
                layer(image: result, placeholder: "—")
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: geo.size.width * (1 - revealFraction))
                    }
                Rectangle()
                    .fill(.white)
                    .frame(width: 1.5)
                    .position(x: geo.size.width * revealFraction, y: geo.size.height / 2)
                    .allowsHitTesting(false)
                VStack {
                    Spacer()
                    Text("Before  |  After")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 6)
                }
                .allowsHitTesting(false)
            }
            .overlay(gestureCapture(hoverEnabled: true))
        }
    }

    private func layer(image: NSImage?, placeholder: String) -> some View {
        ZStack {
            CheckerboardBackground()
            TransformedImage(image: image, zoom: zoom, offset: offset, placeholder: placeholder)
        }
        .clipped()
    }

    private func gestureCapture(hoverEnabled: Bool) -> some View {
        TransformGestureView(
            hoverEnabled: hoverEnabled,
            onPan: { dx, dy in
                offset = CGSize(width: offset.width + dx, height: offset.height + dy)
            },
            onZoom: { factor in zoomBy(factor) },
            onHover: { revealFraction = $0 }
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 10) {
            Button { zoomBy(0.8) } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
            Slider(value: Binding(get: { zoom }, set: { zoom = $0 }), in: minZoom...maxZoom)
            Button { zoomBy(1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=", modifiers: .command)
            Button("Reset") { zoom = 1; offset = .zero }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoom == 1 && offset == .zero)
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func zoomBy(_ factor: CGFloat) {
        zoom = min(maxZoom, max(minZoom, zoom * factor))
    }
}

/// An image with shared scale + offset applied, or a placeholder.
private struct TransformedImage: View {
    let image: NSImage?
    let zoom: CGFloat
    let offset: CGSize
    let placeholder: String

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom)
                .offset(offset)
                .padding(8)
        } else {
            Text(placeholder)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
