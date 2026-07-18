import AppKit
import SwiftUI

/// Borderless, non-activating panel that drops down from the hardware notch
/// and lists hidden status items. Interactive (unlike a pure overlay), but
/// never steals focus from the frontmost app.
@MainActor
final class OverflowPanel: NSPanel {

    static let contentWidth: CGFloat = 380

    private let store: MenuBarStore
    private var clickMonitor: Any?

    init(store: MenuBarStore) {
        self.store = store
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        level = .popUpMenu
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let root = OverflowView(store: store) { [weak self] in
            self?.hide()
        }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    var isShown: Bool { isVisible }

    /// Position flush against the top of the screen, centered on the notch,
    /// and install a click-outside monitor for dismissal.
    func show() {
        store.refresh()
        guard let metrics = store.metrics ?? fallbackMetrics() else { return }

        let screen = metrics.screen
        let height = preferredHeight()
        let width = Self.contentWidth
        let x = metrics.notchCenterX - width / 2
        let y = screen.frame.maxY - height
        setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)

        orderFrontRegardless()
        makeKey()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        orderOut(nil)
    }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    private func preferredHeight() -> CGFloat {
        let menuBar = store.metrics?.menuBarHeight ?? 38
        let rows = max(1, store.axTrusted ? store.hiddenItems.count : 2)
        let rowHeight: CGFloat = 36
        let chrome: CGFloat = 64
        return min(menuBar + chrome + CGFloat(rows) * rowHeight, 560)
    }

    /// Non-notch fallback (external display / older Mac): center under menu bar.
    private func fallbackMetrics() -> NotchMetrics? {
        guard let screen = NSScreen.main else { return nil }
        let center = screen.frame.midX
        return NotchMetrics(
            screen: screen,
            notchXRange: (center - 110)...(center + 110),
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }
}
