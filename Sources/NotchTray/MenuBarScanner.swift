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

    static func scan(bounds: ScanBounds?) -> [MenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var items: [MenuBarItem] = []

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid != ownPID, pid > 0 else { continue }

            let appElement = AXUIElementCreateApplication(pid)
            // Don't stall the scan on unresponsive processes.
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            guard let extras = copyAttribute(appElement, "AXExtrasMenuBar"),
                  CFGetTypeID(extras) == AXUIElementGetTypeID() else { continue }
            let extrasBar = extras as! AXUIElement

            guard let children = copyAttribute(extrasBar, kAXChildrenAttribute) as? [AXUIElement],
                  !children.isEmpty else { continue }

            let appName = app.localizedName ?? "PID \(pid)"

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
                    id: "\(pid)-\(index)",
                    pid: pid,
                    appName: appName,
                    icon: app.icon,
                    detail: detail == appName ? "" : detail,
                    frame: frame,
                    visibility: classify(frame: frame, bounds: bounds),
                    element: child
                ))
            }
        }

        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Opens the item's menu/action as if it had been clicked.
    /// Works even when the item is occluded by the notch or parked off-screen.
    @discardableResult
    static func activate(_ item: MenuBarItem) -> Bool {
        AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
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
