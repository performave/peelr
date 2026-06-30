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
/// The mode Picker lives here; the zoom/pan/reveal state lives in `ComparisonCanvas` so that
/// the constant transform updates during panning/hovering don't re-render (and drop clicks on)
/// the segmented control.
struct ComparisonView: View {
    let original: NSImage?
    let result: NSImage?
    @Binding var mode: CompareMode

    var body: some View {
        VStack(spacing: 8) {
            Picker("Compare", selection: $mode) {
                ForEach(CompareMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ComparisonCanvas(original: original, result: result, mode: mode)
        }
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
    @State private var dragAnchor: CGSize = .zero
    @State private var dragging = false

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
                .background(scrollPinchCapture)
                .gesture(panGesture)
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
                    .shadow(radius: 1)
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
            .background(scrollPinchCapture)
            .gesture(panGesture)
            .onContinuousHover { phase in
                if case .active(let location) = phase, geo.size.width > 0 {
                    revealFraction = min(1, max(0, location.x / geo.size.width))
                }
            }
        }
    }

    private func layer(image: NSImage?, placeholder: String) -> some View {
        ZStack {
            CheckerboardBackground()
            TransformedImage(image: image, zoom: zoom, offset: offset, placeholder: placeholder)
        }
        .clipped()
    }

    // AppKit background: handles only mouse-wheel / trackpad scroll + pinch.
    private var scrollPinchCapture: some View {
        TransformGestureView(
            onPan: { dx, dy in
                offset = CGSize(width: offset.width + dx, height: offset.height + dy)
            },
            onZoom: { factor in
                zoom = min(maxZoom, max(minZoom, zoom * factor))
            }
        )
    }

    // SwiftUI drag-to-pan (mouse and trackpad), so it doesn't fight sibling controls.
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !dragging { dragAnchor = offset; dragging = true }
                offset = CGSize(width: dragAnchor.width + value.translation.width,
                                height: dragAnchor.height + value.translation.height)
            }
            .onEnded { _ in dragging = false }
    }

    private var zoomControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: Binding(get: { zoom }, set: { zoom = $0 }), in: minZoom...maxZoom)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            Button("Reset") { zoom = 1; offset = .zero }
                .disabled(zoom == 1 && offset == .zero)
        }
        .font(.caption)
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
            Text(placeholder).foregroundStyle(.secondary)
        }
    }
}
