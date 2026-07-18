import AppKit
import Observation

/// Observable state: current scan results, notch geometry, and AX trust.
/// Views stay render-only; refresh policy lives here.
@MainActor
@Observable
final class MenuBarStore {
    private(set) var items: [MenuBarItem] = []
    private(set) var metrics: NotchMetrics?
    private(set) var axTrusted = AXIsProcessTrusted()

    /// Called after every refresh so AppKit-side UI (status item badge)
    /// can update without observation plumbing.
    var onRefresh: (() -> Void)?

    private var pollTask: Task<Void, Never>?

    var hiddenItems: [MenuBarItem] { items.filter(\.isHidden) }
    var visibleItems: [MenuBarItem] { items.filter { !$0.isHidden } }

    func refresh() {
        axTrusted = AXIsProcessTrusted()
        metrics = NotchMetrics.detect()
        items = MenuBarScanner.scan(metrics: metrics)
        onRefresh?()
    }

    func startPolling(interval: Duration = .seconds(3)) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func activate(_ item: MenuBarItem) {
        MenuBarScanner.activate(item)
    }

    func requestAccessibility() {
        MenuBarScanner.requestAccessibility()
    }
}
