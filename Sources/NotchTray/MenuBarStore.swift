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
    /// The item currently being revealed and pressed, if any. The island keeps
    /// showing it and marks it busy rather than letting it vanish: revealing an
    /// off-screen item necessarily drags it back into the real menu bar, so a
    /// live list would briefly render it in both places at once.
    private(set) var activatingItemID: String?

    /// Owns the separator item and the move flows.
    var notchManager: NotchManager?

    /// Called after every refresh so AppKit-side UI (status item badge)
    /// can update without observation plumbing.
    var onRefresh: (() -> Void)?

    let capturer = ItemImageCapturer()

    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    /// Monotonic scan ticket. `refresh()` and `rescanNow()` both publish into
    /// `items` from detached scans that can finish out of order, so each write
    /// is gated on still being the newest scan. Without this a slow poll begun
    /// before a move can land after the move's own rescan and reinstate the
    /// pre-move layout, which the move flows then read back as truth.
    private var scanGeneration = 0

    private func nextScanGeneration() -> Int {
        scanGeneration += 1
        return scanGeneration
    }

    var hiddenItems: [MenuBarItem] {
        let hidden = items.filter(\.isHidden)
        // Mid-activation the target is, by design, temporarily visible again.
        // Dropping it from the strip here would collapse the layout under the
        // user's cursor and then bring it back a moment later; keeping it
        // pinned lets the island show it as busy instead.
        guard let activatingItemID, !hidden.contains(where: { $0.id == activatingItemID }),
              let pinned = items.first(where: { $0.id == activatingItemID })
        else { return hidden }
        return (hidden + [pinned]).sorted { $0.frame.minX < $1.frame.minX }
    }

    var visibleItems: [MenuBarItem] { items.filter { !$0.isHidden } }

    /// Kick off a scan on a background thread; publishes results on main.
    /// Coalesces: a refresh arriving while one is in flight is dropped, so
    /// fast polling can never starve the scan → capture chain.
    func refresh(thenCapture: Bool = false) {
        guard refreshTask == nil else { return }
        axTrusted = AXIsProcessTrusted()
        metrics = NotchMetrics.detect()
        let bounds = ScanBounds(metrics: metrics)

        let generation = nextScanGeneration()
        let apps = RunningAppSnapshot.current()

        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            let scanned = await Task.detached(priority: .userInitiated) {
                MenuBarScanner.scan(bounds: bounds, apps: apps)
            }.value
            guard let self, generation == self.scanGeneration else { return }
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
        let generation = nextScanGeneration()
        let apps = RunningAppSnapshot.current()
        let scanned = await Task.detached(priority: .userInitiated) {
            MenuBarScanner.scan(bounds: bounds, apps: apps)
        }.value
        guard generation == scanGeneration else { return }
        items = scanned
        onRefresh?()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let expanded = self?.panelExpanded == true
                // Skip the cycle mid-move: the menu bar is being reshuffled by
                // our own separator, so a scan now captures a transient layout
                // that the move flow would then read back as the real one.
                if self?.isMoving != true {
                    self?.refresh(thenCapture: expanded)
                }
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
        activatingItemID = item.id
        Task {
            await notchManager.activate(item, store: self)
            activatingItemID = nil
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
