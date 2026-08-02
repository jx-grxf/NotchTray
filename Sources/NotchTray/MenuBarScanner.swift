import AppKit
import ApplicationServices

/// Sendable subset of NotchMetrics used for off-main-thread scanning.
struct ScanBounds: Sendable {
    let notchMinX: CGFloat
    let notchMaxX: CGFloat
    let maxVisibleX: CGFloat

    init?(metrics: NotchMetrics?) {
        guard let metrics else { return nil }
        notchMinX = metrics.notchXRange.lowerBound
        notchMaxX = metrics.notchXRange.upperBound
        maxVisibleX = metrics.maxVisibleX
    }
}

/// Discovers status items by walking every running app's `AXExtrasMenuBar`.
///
/// On macOS 26 all status items are *rendered* by the Control Center process,
/// so the classic CGWindowList approach can no longer attribute items to their
/// owning apps. The AX tree, however, is still per-app: each app exposes its
/// items (with global position and size) under the AXExtrasMenuBar attribute,
/// and Control Center exposes the system items (clock, Wi-Fi, battery, ...).
///
/// `scan` is safe to call off the main thread (AX APIs are thread-safe);
/// it can block on unresponsive processes, so callers should not run it on
/// the main thread.
enum MenuBarScanner {

    static func scan(bounds: ScanBounds?, apps: [RunningAppSnapshot]) -> [MenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }

        var items: [MenuBarItem] = []

        for app in apps {
            let pid = app.pid
            let appElement = AXUIElementCreateApplication(pid)
            // Don't stall the scan on unresponsive processes.
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            guard let extras = copyAttribute(appElement, "AXExtrasMenuBar"),
                  CFGetTypeID(extras) == AXUIElementGetTypeID() else { continue }
            let extrasBar = extras as! AXUIElement

            guard let children = copyAttribute(extrasBar, kAXChildrenAttribute) as? [AXUIElement],
                  !children.isEmpty else { continue }

            let appName = app.name

            for (index, child) in children.enumerated() {
                guard let position = pointValue(copyAttribute(child, kAXPositionAttribute)),
                      let size = sizeValue(copyAttribute(child, kAXSizeAttribute)),
                      size.width > 0, size.height > 0,
                      // Menu bar managers host huge helper windows in the
                      // extras bar; real status items are far narrower.
                      size.width < 400 else { continue }

                let frame = CGRect(origin: position, size: size)
                let detail = (copyAttribute(child, kAXDescriptionAttribute) as? String)
                    ?? (copyAttribute(child, kAXTitleAttribute) as? String)
                    ?? ""

                items.append(MenuBarItem(
                    id: Self.identity(of: child, pid: pid, index: index),
                    pid: pid,
                    appName: appName,
                    bundleID: app.bundleID,
                    icon: app.icon,
                    detail: detail == appName ? "" : detail,
                    frame: frame,
                    visibility: classify(frame: frame, bounds: bounds),
                    slot: index,
                    element: child
                ))
            }
        }

        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// A key that survives rescans.
    ///
    /// The position within `AXExtrasMenuBar` is not usable as identity: moving
    /// one item renumbers its neighbours, so an index-derived key reassigns
    /// itself mid-flight. SwiftUI then recycles the wrong rows and the icon
    /// cache — which is keyed by the same id — orphans its entries, which is
    /// what made an item appear twice during a move.
    ///
    /// `AXUIElement` compares by the element it refers to rather than by
    /// pointer, so its hash is stable for as long as the item exists. Index is
    /// only a last resort for the rare element that refuses to hash.
    private static func identity(of element: AXUIElement, pid: pid_t, index: Int) -> String {
        let hash = CFHash(element)
        return hash == 0 ? "\(pid)-idx\(index)" : "\(pid)-\(hash)"
    }

    /// Opens the item's menu/action as if it had been clicked.
    /// Works even when the item is occluded by the notch, but the menu appears
    /// wherever the item currently sits — an item parked off-screen opens its
    /// menu off-screen too, which is why the move flows reveal it first.
    ///
    /// The result is meaningful: a stale element (owning app quit and
    /// relaunched between scans) or an unresponsive process fails here, and
    /// callers should skip the rest of a reveal sequence rather than run its
    /// full visual disruption for a click that did nothing.
    @discardableResult
    static func activate(_ item: MenuBarItem) -> Bool {
        let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        if result != .success {
            DebugLog.log("activate failed: \(item.appName) pid=\(item.pid) code=\(result.rawValue)")
        }
        return result == .success
    }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Classification

    private static func classify(frame: CGRect, bounds: ScanBounds?) -> MenuBarItem.Visibility {
        guard let bounds else { return .visible }
        let tolerance: CGFloat = 1
        if frame.minX >= bounds.notchMaxX - tolerance,
           frame.maxX <= bounds.maxVisibleX + tolerance {
            return .visible
        }
        if frame.maxX > bounds.notchMinX, frame.minX < bounds.notchMaxX {
            return .behindNotch
        }
        return .offscreen
    }

    // MARK: - AX helpers

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func pointValue(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
