import AppKit
import SwiftUI

/// Singleton NSWindowController for the settings window. Created with
/// .fullSizeContentView so macOS 26 renders the liquid glass chrome.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsNavigation.shared.selectedTab = tab
        }
        if shared == nil {
            shared = SettingsWindowController()
        }
        shared?.showWindow(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 700, height: 540)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let window else { return }
        window.title = "Settings"
        window.titleVisibility = .visible
        // .fullSizeContentView only does anything with a transparent titlebar;
        // together they let the sidebar run under the title bar the way System
        // Settings does.
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .automatic
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("SettingsWindow")
        window.minSize = NSSize(width: 620, height: 460)
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView())
    }

    /// Whether this controller currently holds an activation-policy claim.
    /// `showWindow` is reachable twice without an intervening close — the
    /// right-click menu and the island's gear button both call `show()` — and
    /// an unbalanced `enter()` would pin `count` above zero forever, leaving
    /// the Dock icon visible for the rest of the session.
    private var holdsActivationPolicy = false

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        guard !holdsActivationPolicy else { return }
        holdsActivationPolicy = true
        AppActivationPolicy.enter()
    }

    func windowWillClose(_ notification: Notification) {
        if holdsActivationPolicy {
            holdsActivationPolicy = false
            AppActivationPolicy.leave()
        }
        Self.shared = nil
    }
}
