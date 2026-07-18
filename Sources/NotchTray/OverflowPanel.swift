import AppKit
import SwiftUI

/// Borderless, non-activating panel hosting the notch island. The window is
/// sized generously and shown instantly; the SwiftUI content animates between
/// a collapsed notch-sized state (invisible black-on-black) and the expanded
/// island, per the Dynamic Island choreography.
@MainActor
final class OverflowPanel: NSPanel {

    private let store: MenuBarStore
    /// Reports hover state changes so the owner can manage auto-close.
    var onHoverChange: ((Bool) -> Void)?

    private var globalClickMonitor: Any?

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

        let root = OverflowView(
            store: store,
            onHover: { [weak self] inside in self?.onHoverChange?(inside) },
            onClose: { [weak self] in self?.hide() }
        )
        contentView = NSHostingView(rootView: root)
    }

    override var canBecomeKey: Bool { true }

    var isShown: Bool { isVisible }

    func show() {
        guard !isShown else { return }
        store.refresh()
        guard let metrics = store.metrics else { return }

        store.capturer.requestPermissionIfNeeded()

        // Generous fixed frame; the island animates inside it.
        let width: CGFloat = 640
        let height: CGFloat = metrics.menuBarHeight + 160
        let screen = metrics.screen
        setFrame(CGRect(
            x: metrics.notchCenterX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        ), display: true)

        orderFrontRegardless()

        Task { await store.captureIcons() }

        // Let the window land on screen before the expand spring starts.
        DispatchQueue.main.async { [store] in
            store.panelExpanded = true
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        guard isShown else { return }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        store.panelExpanded = false
        // Remove the window only after the collapse spring has finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.store.panelExpanded else { return }
            self.orderOut(nil)
        }
    }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    override func mouseDown(with event: NSEvent) {
        // Clicks landing on the transparent margin around the island.
        hide()
    }
}
