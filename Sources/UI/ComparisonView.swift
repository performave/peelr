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

/// Describes background work so the Result pane can show a progress bar.
struct WorkProgress: Equatable {
    /// Whether the underlying work is currently running.
    var active: Bool = false
    /// Real progress 0…1 for determinate work (model download); `nil` means indeterminate
    /// (a single opaque inference pass — the bar trickles instead).
    var fraction: Double? = nil
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
    var progress: WorkProgress = WorkProgress()

    var body: some View {
        // The mode Picker lives in the window toolbar (see MainWindow) so the preview's
        // high-frequency hover/pan updates can never starve its clicks.
        ComparisonCanvas(original: original, result: result, mode: mode, progress: progress)
    }
}

/// Owns the transform state and renders the panes. Isolated so its frequent updates stay local.
private struct ComparisonCanvas: View {
    let original: NSImage?
    let result: NSImage?
    let mode: CompareMode
    let progress: WorkProgress

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
                pane(title: "Result", image: result, placeholder: "Result appears here",
                     showsProgress: true)
            }
        case .reveal:
            revealPane
        }
    }

    private func pane(title: String, image: NSImage?, placeholder: String,
                      showsProgress: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            layer(image: image, placeholder: placeholder)
                .overlay(gestureCapture(hoverEnabled: false))
                .overlay(alignment: .bottom) {
                    if showsProgress {
                        TrickleProgressBar(progress: progress)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                }
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
                layer(image: result, placeholder: "Result appears here")
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
            .overlay(alignment: .bottom) {
                TrickleProgressBar(progress: progress)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
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

/// A slim progress bar pinned to the bottom of the Result pane.
///
/// Determinate work (the model download) drives it directly from `progress.fraction`.
/// Indeterminate work (a single inference pass) has no intermediate signal, so the bar
/// *trickles* toward ~90% while running. In both cases it enforces a minimum on-screen sweep
/// so work that finishes almost instantly still reads as a deliberate fill-and-fade rather than
/// a glitchy flash.
private struct TrickleProgressBar: View {
    let progress: WorkProgress

    @State private var value: Double = 0
    @State private var visible = false
    @State private var startedAt = Date.distantPast
    @State private var driver: Task<Void, Never>?

    private let minVisible: TimeInterval = 0.7

    var body: some View {
        GeometryReader { geo in
            // A thin, track-less accent line that grows left→right (Safari-style), so it reads
            // as loading progress rather than a second slider competing with the zoom control.
            Capsule()
                .fill(Color.accentColor)
                .frame(width: max(0, geo.size.width * value))
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .accentColor.opacity(0.5), radius: 3)
        }
        .frame(height: 3)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: visible)
        .onAppear { if progress.active { start() } }
        .onChange(of: progress.active) { _, active in active ? start() : finish() }
        .onChange(of: progress.fraction) { _, f in
            if let f, progress.active {
                withAnimation(.easeOut(duration: 0.2)) { value = f }
            }
        }
    }

    private func start() {
        driver?.cancel()
        startedAt = Date()
        value = progress.fraction ?? 0
        visible = true
        // Only trickle for indeterminate work; determinate work is driven by `fraction`.
        guard progress.fraction == nil else { return }
        driver = Task { @MainActor in
            while !Task.isCancelled && value < 0.9 {
                try? await Task.sleep(nanoseconds: 70_000_000)
                guard !Task.isCancelled else { return }
                // Ease toward 0.9, slowing as it approaches so it never quite arrives.
                withAnimation(.linear(duration: 0.07)) {
                    value += (0.9 - value) * 0.12 + 0.01
                }
            }
        }
    }

    private func finish() {
        driver?.cancel()
        driver = Task { @MainActor in
            let remaining = max(0, minVisible - Date().timeIntervalSince(startedAt))
            let fill = max(0.2, remaining)
            withAnimation(.easeInOut(duration: fill)) { value = 1 }
            try? await Task.sleep(nanoseconds: UInt64(fill * 1_000_000_000))
            guard !Task.isCancelled else { return }
            visible = false
            try? await Task.sleep(nanoseconds: 260_000_000)   // let the fade finish
            guard !Task.isCancelled else { return }
            value = 0
        }
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
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}
