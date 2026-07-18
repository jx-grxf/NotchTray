import AppKit
import Observation

/// Observable state: current scan results, notch geometry, AX trust, and
/// captured item icons. Views stay render-only; refresh policy lives here.
///
/// The AX scan can block on unresponsive processes, so it runs on a
/// background thread; the panel opens instantly from cached results.
@MainActor
@Observable
final class MenuBarStore {
    private(set) var items: [MenuBarItem] = []
    private(set) var metrics: NotchMetrics?
    private(set) var axTrusted = AXIsProcessTrusted()
    /// Real rendered menu bar icons, keyed by item id (Screen Recording).
    private(set) var captures: [String: CGImage] = [:]
    /// Drives the island's expand/collapse spring animation.
    var panelExpanded = false
    /// Edit mode: the island shows all items with hide/restore actions.
    var editMode = false
    /// A ⌘-drag move is in progress; the strip disables itself meanwhile.
    private(set) var isMoving = false

    /// Owns the separator item and the move flows.
    var notchManager: NotchManager?

    /// Called after every refresh so AppKit-side UI (status item badge)
    /// can update without observation plumbing.
    var onRefresh: (() -> Void)?

    let capturer = ItemImageCapturer()

    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    var hiddenItems: [MenuBarItem] { items.filter(\.isHidden) }
    var visibleItems: [MenuBarItem] { items.filter { !$0.isHidden } }

    /// Kick off a scan on a background thread; publishes results on main.
    /// Coalesces: a refresh arriving while one is in flight is dropped, so
    /// fast polling can never starve the scan → capture chain.
    func refresh(thenCapture: Bool = false) {
        guard refreshTask == nil else { return }
        axTrusted = AXIsProcessTrusted()
        metrics = NotchMetrics.detect()
        let bounds = ScanBounds(metrics: metrics)

        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            let scanned = await Task.detached(priority: .userInitiated) {
                MenuBarScanner.scan(bounds: bounds)
            }.value
            guard let self else { return }
            self.items = scanned
            self.onRefresh?()
            if thenCapture {
                await self.captureIcons()
            }
        }
    }

    func captureIcons() async {
        let targets = editMode ? items : hiddenItems
        let fresh = await capturer.capture(items: targets)
        // Merge instead of replace: a transiently failed capture (items
        // resize/move while updating) keeps its last good icon rather than
        // flickering back to the app-icon fallback.
        captures.merge(fresh) { _, new in new }
        // Drop entries for items that no longer exist at all.
        let liveIDs = Set(items.map(\.id))
        captures = captures.filter { liveIDs.contains($0.key) }
    }

    /// Awaitable scan used by move flows that need fresh positions.
    func rescanNow() async {
        axTrusted = AXIsProcessTrusted()
        metrics = NotchMetrics.detect()
        let bounds = ScanBounds(metrics: metrics)
        items = await Task.detached(priority: .userInitiated) {
            MenuBarScanner.scan(bounds: bounds)
        }.value
        onRefresh?()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let expanded = self?.panelExpanded == true
                self?.refresh(thenCapture: expanded)
                // Fast cycle while the island is open so live tiles
                // (CPU %, clocks, ...) stay current; relaxed otherwise.
                try? await Task.sleep(for: .seconds(expanded ? 1 : 3))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func activate(_ item: MenuBarItem) {
        guard let notchManager, !isMoving else {
            MenuBarScanner.activate(item)
            return
        }
        isMoving = true
        Task {
            await notchManager.activate(item, store: self)
            isMoving = false
        }
    }

    func hideIntoNotch(_ item: MenuBarItem) {
        guard let notchManager, !isMoving else { return }
        isMoving = true
        Task {
            await notchManager.hide(item, store: self)
            await captureIcons()
            isMoving = false
        }
    }

    func restoreFromNotch(_ item: MenuBarItem) {
        guard let notchManager, !isMoving else { return }
        isMoving = true
        Task {
            await notchManager.restore(item, store: self)
            await captureIcons()
            isMoving = false
        }
    }

    func requestAccessibility() {
        MenuBarScanner.requestAccessibility()
    }
}
