import AppKit
import ApplicationServices

/// A single status item in the menu bar, discovered via the Accessibility API.
struct MenuBarItem: Identifiable {
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
    let icon: NSImage?
    /// Optional AX description, e.g. "Battery" for Control Center items.
    let detail: String
    /// Global frame in top-left-origin coordinates (as reported by AX).
    let frame: CGRect
    let visibility: Visibility
    /// The AX element backing this item; used to activate it.
    let element: AXUIElement

    var isHidden: Bool { visibility != .visible }
}
