import SwiftUI

/// AppKit-backed capture for ONLY the events SwiftUI can't handle: the mouse wheel and trackpad
/// scroll/pinch. Clicks, drag-to-pan, and hover stay in SwiftUI (see `ComparisonView`) so they
/// don't disrupt sibling controls like the mode tabs. Installed as a `.background`, never on top.
struct TransformGestureView: NSViewRepresentable {
    var onPan: (CGFloat, CGFloat) -> Void
    var onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> GestureNSView { GestureNSView() }

    func updateNSView(_ view: GestureNSView, context: Context) {
        view.onPan = onPan
        view.onZoom = onZoom
    }
}

final class GestureNSView: NSView {
    var onPan: ((CGFloat, CGFloat) -> Void)?
    var onZoom: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            onPan?(event.scrollingDeltaX, event.scrollingDeltaY) // trackpad two-finger pan
        } else {
            onZoom?(1 + event.scrollingDeltaY * 0.01)            // mouse wheel zoom
        }
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + event.magnification)                         // trackpad pinch zoom
    }
}
