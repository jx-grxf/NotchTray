import AppKit
import SwiftUI

/// Borderless, non-activating panel hosting the notch island. The window is
/// sized generously and shown instantly; the SwiftUI content animates between
/// a collapsed notch-sized state (invisible black-on-black) and the expanded
/// island, per the Dynamic Island choreography.
///
/// Auto-close does not rely on hover tracking (fragile across overlapping
/// windows): while shown, a watcher polls the global mouse location and
/// closes the island once the cursor has left the notch+island region.
@MainActor
final class OverflowPanel: NSPanel {

    private let store: MenuBarStore
    private let hosting: NSHostingView<OverflowView>

    private var globalClickMonitor: Any?
    private var containmentTask: Task<Void, Never>?

    init(store: MenuBarStore) {
        self.store = store
        let root = OverflowView(store: store)
        self.hosting = NSHostingView(rootView: root)
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

        hosting.rootView = OverflowView(store: store) { [weak self] in
            self?.hide()
        }
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    var isShown: Bool { isVisible }

    func show() {
        guard !isShown else { return }
        // Opens instantly from cached scan results; a fresh background scan
        // and icon capture update the strip moments later.
        store.refresh(thenCapture: true)
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

        // Let the window land on screen before the expand spring starts.
        DispatchQueue.main.async { [store] in
            store.panelExpanded = true
        }

        startContainmentWatch()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        guard isShown else { return }
        containmentTask?.cancel()
        containmentTask = nil
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        store.panelExpanded = false
        store.editMode = false
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

    // MARK: - Mouse containment

    private func startContainmentWatch() {
        containmentTask?.cancel()
        containmentTask = Task { [weak self] in
            let clock = ContinuousClock()
            var outsideSince: ContinuousClock.Instant?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, self.isShown else { return }
                // Synthetic ⌘-drags move the cursor across the menu bar;
                // don't let that count as the user leaving.
                if self.store.isMoving {
                    outsideSince = nil
                    continue
                }
                if self.keepOpenRegion().contains(NSEvent.mouseLocation) {
                    outsideSince = nil
                } else if let since = outsideSince {
                    if clock.now - since > .milliseconds(Int(Prefs.autoCloseDelay * 1000)) {
                        self.hide()
                        return
                    }
                } else {
                    outsideSince = clock.now
                }
            }
        }
    }

    /// Notch + expanded island, with a small forgiveness margin
    /// (bottom-left-origin global coordinates, same as NSEvent.mouseLocation).
    private func keepOpenRegion() -> CGRect {
        let island = hosting.fittingSize
        let f = frame
        return CGRect(
            x: f.midX - island.width / 2 - 16,
            y: f.maxY - island.height - 28,
            width: island.width + 32,
            height: island.height + 28
        )
    }
}
