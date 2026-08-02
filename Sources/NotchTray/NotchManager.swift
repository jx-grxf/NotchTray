import AppKit

/// Lets the user move other apps' status items "into the notch".
///
/// Mechanism (the same one Ice/Bartender use): NotchTray owns an invisible
/// separator status item. Expanding its length to several thousand points
/// pushes every item positioned left of it off-screen; the island already
/// detects and renders those. Items are moved across the separator with a
/// synthetic ⌘-drag — macOS offers no API to reposition other apps' items,
/// but the automated version of the user's own gesture works.
@MainActor
final class NotchManager {

    private var separator: NSStatusItem?
    private let expandedLength: CGFloat = 5000
    private let collapsedLength: CGFloat = 8
    private(set) var isExpanded = false

    /// Makes NotchTray's own windows (island, hover zone) click-through
    /// while a synthetic drag runs — they overlap the notch area and would
    /// otherwise swallow the drag's mouse events.
    var setInteractionPassthrough: ((Bool) -> Void)?

    /// Create the separator and activate hiding. On first run the separator
    /// appears at the left end of the status area, so expanding hides
    /// nothing until the user moves items across it.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: collapsedLength)
        item.autosaveName = "NotchTraySeparator"
        item.button?.title = ""
        separator = item
        expand()
    }

    func expand() {
        separator?.length = expandedLength
        isExpanded = true
    }

    func collapse() {
        separator?.length = collapsedLength
        isExpanded = false
    }

    /// Separator frame in global bottom-left coordinates (x matches AX).
    private var separatorFrame: CGRect? {
        separator?.button?.window?.frame
    }

    // MARK: - Flows

    /// Move a visible item left of the separator, then re-expand.
    func hide(_ item: MenuBarItem, store: MenuBarStore) async {
        collapse()
        try? await Task.sleep(for: .milliseconds(350))
        await store.rescanNow()

        guard let fresh = store.items.first(where: { $0.id == item.id }),
              let sep = separatorFrame else {
            expand()
            return
        }
        let y = fresh.frame.midY
        setInteractionPassthrough?(true)
        await ItemMover.cmdDrag(
            from: CGPoint(x: fresh.frame.midX, y: y),
            to: CGPoint(x: sep.minX - 25, y: y)
        )
        setInteractionPassthrough?(false)
        try? await Task.sleep(for: .milliseconds(250))
        expand()
        try? await Task.sleep(for: .milliseconds(250))
        await store.rescanNow()
    }

    /// Bring a notch-hidden item back to the visible section.
    func restore(_ item: MenuBarItem, store: MenuBarStore) async {
        collapse()
        try? await Task.sleep(for: .milliseconds(350))
        await store.rescanNow()

        guard let fresh = store.items.first(where: { $0.id == item.id }),
              fresh.frame.minX > 0,
              let sep = separatorFrame else {
            expand()
            return
        }
        let y = fresh.frame.midY
        // Land clearly right of both the separator and the notch band.
        var targetX = sep.maxX + 25
        if let metrics = NotchMetrics.detect(), targetX < metrics.minVisibleX + 10 {
            targetX = metrics.minVisibleX + 10
        }
        setInteractionPassthrough?(true)
        await ItemMover.cmdDrag(
            from: CGPoint(x: fresh.frame.midX, y: y),
            to: CGPoint(x: targetX, y: y)
        )
        setInteractionPassthrough?(false)
        try? await Task.sleep(for: .milliseconds(250))
        expand()
        try? await Task.sleep(for: .milliseconds(250))
        await store.rescanNow()
    }

    /// Open a hidden item's menu. Off-screen items would open their menus
    /// off-screen, so briefly collapse the separator to bring the item back
    /// into view, press it there, and re-expand once the menu is done.
    func activate(_ item: MenuBarItem, store: MenuBarStore) async {
        switch item.visibility {
        case .visible, .behindNotch:
            MenuBarScanner.activate(item)
        case .offscreen:
            collapse()
            try? await Task.sleep(for: .milliseconds(350))
            await store.rescanNow()

            let pressed: Bool
            if let fresh = store.items.first(where: { $0.id == item.id }),
               fresh.frame.minX > 0 {
                pressed = MenuBarScanner.activate(fresh)
            } else {
                // Not ours (e.g. parked by another manager): best effort.
                pressed = MenuBarScanner.activate(item)
                NSRunningApplication(processIdentifier: item.pid)?.activate()
            }

            if pressed {
                // Hold the reveal only while the menu is actually open. The
                // timeout is the ceiling, not the plan: menus that never
                // report closing — Electron apps tend to draw their own
                // window rather than an AXMenu — fall back to it.
                await MenuMonitor.waitForMenuToClose(pid: item.pid, timeout: .seconds(12))
            } else {
                // The press did nothing, so there is no menu to wait for and
                // no reason to keep every hidden item dumped in the menu bar.
                DebugLog.log("activate: press failed, collapsing immediately")
            }

            expand()
            // Let the window server settle the new layout before asking AX
            // where anything is, as hide()/restore() do.
            try? await Task.sleep(for: .milliseconds(250))
            await store.rescanNow()
        }
    }
}

/// Posts a synthetic ⌘-drag so macOS reorders a status item, exactly as if
/// the user had dragged it by hand. The cursor position is restored after.
@MainActor
enum ItemMover {

    /// A synthetic `leftMouseDown` changes window-server-global button state,
    /// not merely this app's. Between it and the matching `leftMouseUp` the
    /// button is logically held for the whole system; if the process dies in
    /// that window, macOS keeps it held until the user's next physical click,
    /// which then lands as a stray drag on whatever is under the cursor.
    ///
    /// Every exit from `cmdDrag` therefore has to release the button —
    /// including cancellation and termination — and a crash has to be repaired
    /// on the next launch, which is what this flag records.
    nonisolated private static let dragInFlightKey = "itemMoverDragInFlight"

    /// Posts a bare left-mouse-up at the current cursor location. Harmless when
    /// no button is held: the window server ignores a redundant release.
    nonisolated static func releaseMouseButton() {
        let source = CGEventSource(stateID: .hidSystemState)
        let location = CGEvent(source: nil)?.location ?? .zero
        CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
        UserDefaults.standard.removeObject(forKey: dragInFlightKey)
    }

    /// Releases the button if a previous run died mid-drag. Call once at launch.
    nonisolated static func recoverInterruptedDrag() {
        guard UserDefaults.standard.bool(forKey: dragInFlightKey) else { return }
        DebugLog.log("mover: recovering from an interrupted drag")
        releaseMouseButton()
    }

    static func cmdDrag(from: CGPoint, to: CGPoint) async {
        let restore = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        post(.mouseMoved, from)
        try? await Task.sleep(for: .milliseconds(60))

        // Mark before pressing, clear after releasing, so the recovery flag can
        // only ever err on the side of an extra harmless mouse-up.
        UserDefaults.standard.set(true, forKey: dragInFlightKey)
        post(.leftMouseDown, from)

        await withTaskCancellationHandler {
            try? await Task.sleep(for: .milliseconds(80))

            let steps = 12
            for step in 1...steps {
                if Task.isCancelled { break }
                let t = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y)
                post(.leftMouseDragged, point)
                try? await Task.sleep(for: .milliseconds(18))
            }

            try? await Task.sleep(for: .milliseconds(80))
            post(.leftMouseUp, to)
        } onCancel: {
            releaseMouseButton()
        }

        UserDefaults.standard.removeObject(forKey: dragInFlightKey)
        try? await Task.sleep(for: .milliseconds(60))

        if let restore {
            CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: restore,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
    }
}
