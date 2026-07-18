import AppKit

/// Invisible, non-activating panel covering exactly the hardware notch band.
/// Its only job is mouse tracking: moving the cursor into the notch opens
/// the overflow island, leaving it schedules a close.
@MainActor
final class NotchHoverZone: NSPanel {

    init(metrics: NotchMetrics, onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        // Wider than the notch itself so the target is easy to hit.
        let horizontalSlop: CGFloat = 24
        let rect = CGRect(
            x: metrics.notchXRange.lowerBound - horizontalSlop,
            y: metrics.screen.frame.maxY - metrics.menuBarHeight,
            width: metrics.notchWidth + horizontalSlop * 2,
            height: metrics.menuBarHeight
        )
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = .statusBar
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        contentView = TrackingView(frame: rect, onEnter: onEnter, onExit: onExit)
        setFrame(rect, display: false)
        orderFrontRegardless()
    }
}

private final class TrackingView: NSView {
    private let onEnter: () -> Void
    private let onExit: () -> Void

    init(frame: NSRect, onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}
