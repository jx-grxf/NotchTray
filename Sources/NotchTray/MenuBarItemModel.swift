import AppKit
import ApplicationServices

/// A single status item in the menu bar, discovered via the Accessibility API.
///
/// @unchecked Sendable: immutable struct; AXUIElement is a thread-safe CF
/// type and NSImage is not mutated after creation. Items are produced on a
/// background scan thread and consumed on the main actor.
struct MenuBarItem: Identifiable, @unchecked Sendable {
    enum Visibility {
        /// Fully inside the visible right-hand menu bar region.
        case visible
        /// Frame intersects the hardware notch band.
        case behindNotch
        /// Pushed off-screen or into the app-menu region (e.g. overflowed
        /// or parked off-screen by a menu bar manager).
        case offscreen
    }

    let id: String
    let pid: pid_t
    let appName: String
    let bundleID: String
    let icon: NSImage?
    /// Optional AX description, e.g. "Battery" for Control Center items.
    let detail: String
    /// Global frame in top-left-origin coordinates (as reported by AX).
    let frame: CGRect
    let visibility: Visibility
    /// Position within the owning app's extras menu bar. Only used to tell
    /// apart several items of the same app that carry no description.
    let slot: Int
    /// The AX element backing this item; used to activate it.
    let element: AXUIElement

    var isHidden: Bool { visibility != .visible }

    /// Key for the captured-icon cache.
    ///
    /// Deliberately not `id`: that one is derived from the AX element so it
    /// survives a rescan, but it changes when the owning app restarts and it
    /// means nothing across launches. A capture is only obtainable while an
    /// item is on screen, so the cache has to outlive both — otherwise an item
    /// that is already hidden at launch can never show its real icon.
    var cacheKey: String {
        detail.isEmpty ? "\(bundleID)#\(slot)" : "\(bundleID)#\(detail)"
    }
}
