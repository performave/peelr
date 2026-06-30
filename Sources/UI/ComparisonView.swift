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
/// Side-by-side shares one transform across both panes (pan/zoom mirrors). Reveal layers the
/// result over the original behind a curtain that follows the mouse — each side is clipped to
/// its *own* background so the result's transparency shows the checkerboard, not the original.
struct ComparisonView: View {
    let original: NSImage?
    let result: NSImage?
    @Binding var mode: CompareMode

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var revealFraction: CGFloat = 0.5

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 12

    var body: some View {
        VStack(spacing: 8) {
            Picker("Compare", selection: $mode) {
                ForEach(CompareMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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

    // MARK: - Side by side

    private func pane(title: String, image: NSImage?, placeholder: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            layer(image: image, placeholder: placeholder)
                .overlay(gestureCapture(hoverEnabled: false))
        }
    }

    // MARK: - Reveal

    private var revealPane: some View {
        GeometryReader { geo in
            ZStack {
                // Before (original) on the right side of the curtain.
                layer(image: original, placeholder: "Drop image here")
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: geo.size.width * (1 - revealFraction))
                    }
                // After (result, over its own checkerboard) on the left.
                layer(image: result, placeholder: "—")
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * revealFraction)
                    }
                Rectangle()
                    .fill(.white)
                    .frame(width: 1.5)
                    .shadow(radius: 1)
                    .position(x: geo.size.width * revealFraction, y: geo.size.height / 2)
                    .allowsHitTesting(false)
                VStack {
                    Spacer()
                    Text("After  |  Before")
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

    // MARK: - Building blocks

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
            onZoom: { factor in
                zoom = min(maxZoom, max(minZoom, zoom * factor))
            },
            onHover: { revealFraction = $0 }
        )
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
