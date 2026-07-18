import AppKit

/// Reference-counted switch between the base activation policy and .regular,
/// so the settings window can come to the foreground. The base policy is
/// .accessory (menu-bar-only) unless the user enabled "Show in Dock".
@MainActor
enum AppActivationPolicy {
    private static var count = 0

    static var basePolicy: NSApplication.ActivationPolicy {
        Prefs.showInDock ? .regular : .accessory
    }

    /// Apply the user's preferred base policy (launch, or pref change).
    static func applyBasePolicy() {
        guard count == 0 else { return }
        NSApp.setActivationPolicy(basePolicy)
    }

    static func enter() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(basePolicy)
        }
    }
}
