import AppKit
import Carbon.HIToolbox

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private let store = MenuBarStore()
    private var statusItem: NSStatusItem?
    private var panel: OverflowPanel?
    private var hoverZone: NotchHoverZone?
    private var closeTask: Task<Void, Never>?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = OverflowPanel(store: store)
        panel.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "menubar.arrow.down.rectangle",
                accessibilityDescription: "NotchTray"
            )
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        store.onRefresh = { [weak self] in self?.updateBadge() }
        store.refresh()
        store.startPolling()
        installHoverZone()
        registerHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if !AXIsProcessTrusted() {
            MenuBarScanner.requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopPolling()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    func togglePanel() {
        closeTask?.cancel()
        panel?.toggle()
    }

    // MARK: - Hover choreography

    private func installHoverZone() {
        hoverZone?.orderOut(nil)
        hoverZone = nil
        guard let metrics = NotchMetrics.detect() else { return }
        hoverZone = NotchHoverZone(
            metrics: metrics,
            onEnter: { [weak self] in self?.notchHovered() },
            onExit: { [weak self] in self?.hoverChanged(false) }
        )
    }

    private func notchHovered() {
        closeTask?.cancel()
        // Only expand when there is something to show (or to ask for).
        guard !store.axTrusted || !store.hiddenItems.isEmpty else { return }
        panel?.show()
    }

    private func hoverChanged(_ inside: Bool) {
        closeTask?.cancel()
        guard !inside else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.panel?.hide()
        }
    }

    @objc private func screensChanged() {
        panel?.hide()
        installHoverZone()
        store.refresh()
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        let count = store.hiddenItems.count
        button.title = count > 0 ? " \(count)" : ""
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Grant Accessibility Access…",
                         action: #selector(grantAccess), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchTray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items { item.target = item.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
        }
    }

    @objc private func refreshNow() {
        store.refresh()
    }

    @objc private func grantAccess() {
        MenuBarScanner.requestAccessibility()
    }

    // MARK: - Global hotkey (⌃⌥N)

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hotkey events on the main event loop.
            MainActor.assumeIsolated { delegate.togglePanel() }
            return noErr
        }, 1, &eventType, selfPtr, &hotKeyHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E54_5259), id: 1) // "NTRY"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
