import SwiftUI

/// AppKit-backed gesture capture for smooth trackpad zoom/pan. SwiftUI's `MagnificationGesture`
/// handles pinch but not two-finger scroll or the mouse wheel, so we drop down to NSView:
///   • trackpad two-finger scroll → pan
///   • pinch → zoom
///   • mouse wheel → zoom
///   • click-drag → pan
///   • mouse move → hover position (for the reveal curtain)
struct TransformGestureView: NSViewRepresentable {
    var hoverEnabled: Bool = false
    var onPan: (CGFloat, CGFloat) -> Void
    var onZoom: (CGFloat) -> Void
    var onHover: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> GestureNSView { GestureNSView() }

    func updateNSView(_ view: GestureNSView, context: Context) {
        view.hoverEnabled = hoverEnabled
        view.onPan = onPan
        view.onZoom = onZoom
        view.onHover = onHover
    }
}

final class GestureNSView: NSView {
    var hoverEnabled = false
    var onPan: ((CGFloat, CGFloat) -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onHover: ((CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            onPan?(event.scrollingDeltaX, event.scrollingDeltaY) // trackpad pan
        } else {
            onZoom?(1 + event.scrollingDeltaY * 0.01)            // mouse wheel zoom
        }
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + event.magnification)                         // pinch zoom
    }

    override func mouseDragged(with event: NSEvent) {
        onPan?(event.deltaX, event.deltaY)                       // grab-to-pan
    }

    override func mouseMoved(with event: NSEvent) {
        guard hoverEnabled, bounds.width > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        onHover?(max(0, min(1, p.x / bounds.width)))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }
}
