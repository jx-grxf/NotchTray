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
    private let iconCache = IconCache()

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
        // Photograph everything, not just what is hidden. A hidden item sits
        // far off-screen where ScreenCaptureKit will not follow, so its only
        // chance at a real icon is a capture taken while it was still visible.
        let fresh = await capturer.capture(items: items)

        for (id, image) in fresh {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            iconCache.store(image, for: item.cacheKey)
        }

        // Rebuild the lookup the views read, falling back to whatever the
        // cache still holds for items that could not be captured this round.
        var resolved: [String: CGImage] = [:]
        for item in items {
            if let image = iconCache[item.cacheKey] {
                resolved[item.id] = image
            }
        }
        captures = resolved
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
            var cyclesSinceCapture = 0
            while !Task.isCancelled {
                let expanded = self?.panelExpanded == true

                // An item can only be photographed while it is on screen, so
                // the cache has to be topped up in the background too — by the
                // time the user opens the island, the interesting items are
                // already parked off-screen where no capture is possible.
                cyclesSinceCapture += 1
                let capture = expanded || cyclesSinceCapture >= 10
                if capture { cyclesSinceCapture = 0 }

                // Skip the cycle mid-move: the menu bar is being reshuffled by
                // our own separator, so a scan now captures a transient layout
                // that the move flow would then read back as the real one.
                if self?.isMoving != true {
                    self?.refresh(thenCapture: capture)
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

    /// Runs a move flow with a hard ceiling on how long it may hold `isMoving`.
    ///
    /// Every flow drives the separator: it collapses, the items spill into the
    /// visible menu bar, and only the tail of the flow puts them back. A flow
    /// that never returns therefore does not just block the next click — it
    /// leaves the menu bar permanently unpacked with no way out but a relaunch.
    /// The watchdog exists so that state is always recoverable.
    private func runMove(_ body: @escaping () async -> Void) {
        guard let notchManager, !isMoving else { return }
        isMoving = true

        Task {
            let work = Task { await body() }
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                DebugLog.log("move: watchdog fired, forcing recovery")
                work.cancel()
            }

            await work.value
            watchdog.cancel()

            // Whatever happened, put the menu bar back the way it was.
            notchManager.expand()
            activatingItemID = nil
            isMoving = false
            await rescanNow()
        }
    }

    func activate(_ item: MenuBarItem) {
        guard let notchManager, !isMoving else {
            MenuBarScanner.activate(item)
            return
        }
        activatingItemID = item.id
        runMove { [weak self] in
            guard let self else { return }
            await notchManager.activate(item, store: self)
        }
    }

    func hideIntoNotch(_ item: MenuBarItem) {
        guard let notchManager else { return }
        runMove { [weak self] in
            guard let self else { return }
            await notchManager.hide(item, store: self)
            await self.captureIcons()
        }
    }

    func restoreFromNotch(_ item: MenuBarItem) {
        guard let notchManager else { return }
        runMove { [weak self] in
            guard let self else { return }
            await notchManager.restore(item, store: self)
            await self.captureIcons()
        }
    }

    func requestAccessibility() {
        MenuBarScanner.requestAccessibility()
    }
}
