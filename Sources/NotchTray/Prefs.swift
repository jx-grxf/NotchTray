import Foundation

/// UserDefaults-backed preferences, readable from AppKit code paths.
/// SwiftUI panes bind to the same keys via @AppStorage.
enum Prefs {
    static let openOnHoverKey = "openOnHover"
    static let autoCloseDelayKey = "autoCloseDelay"
    static let showInDockKey = "showInDock"
    static let updateChannelKey = "updateChannel"

    /// Expand the island when the cursor touches the notch (default on).
    static var openOnHover: Bool {
        UserDefaults.standard.object(forKey: openOnHoverKey) as? Bool ?? true
    }

    /// Seconds the cursor may stay outside the island before it closes.
    static var autoCloseDelay: Double {
        let value = UserDefaults.standard.double(forKey: autoCloseDelayKey)
        return value == 0 ? 0.6 : value
    }

    /// Show the app in the Dock (default off — menu-bar-only).
    static var showInDock: Bool {
        UserDefaults.standard.bool(forKey: showInDockKey)
    }
}
