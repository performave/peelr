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

/// Before/after viewer with shared zoom + pan. In side-by-side mode both panes share one
/// transform, so panning/zooming either mirrors the other. In reveal mode the result is
/// layered over the original and unveiled by a curtain that follows the mouse.
struct ComparisonView: View {
    let original: NSImage?
    let result: NSImage?
    @Binding var mode: CompareMode

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
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
            ZStack {
                CheckerboardBackground()
                TransformedImage(image: image, zoom: zoom, offset: offset, placeholder: placeholder)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
        }
    }

    // MARK: - Reveal

    private var revealPane: some View {
        GeometryReader { geo in
            ZStack {
                CheckerboardBackground()
                TransformedImage(image: original, zoom: zoom, offset: offset, placeholder: "Drop image here")
                // Result clipped to the curtain width (left of the divider).
                TransformedImage(image: result, zoom: zoom, offset: offset, placeholder: "—")
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * revealFraction)
                    }
                // Divider handle.
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
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    revealFraction = min(1, max(0, location.x / geo.size.width))
                }
            }
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
        }
    }

    // MARK: - Controls

    private var zoomControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { zoom },
                set: { zoom = $0; lastZoom = $0 }
            ), in: minZoom...maxZoom)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            Button("Reset") { resetTransform() }
                .disabled(zoom == 1 && offset == .zero)
        }
        .font(.caption)
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(maxZoom, max(minZoom, lastZoom * value))
            }
            .onEnded { _ in lastZoom = zoom }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func resetTransform() {
        zoom = 1; lastZoom = 1
        offset = .zero; lastOffset = .zero
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
