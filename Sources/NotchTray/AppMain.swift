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
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivationPolicy.applyBasePolicy()
        panel = OverflowPanel(store: store)

        // Separator first: on macOS 26 new status items insert to the right,
        // so the main icon created afterwards lands on the visible side.
        let manager = NotchManager()
        manager.install()
        manager.setInteractionPassthrough = { [weak self] passthrough in
            self?.panel?.ignoresMouseEvents = passthrough
            self?.hoverZone?.ignoresMouseEvents = passthrough
        }
        store.notchManager = manager

        createStatusItem()

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

        // If our own icon ended up left of the separator (hidden), pull it
        // back to the visible side.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.rescueOwnIconIfHidden()
        }
    }

    private func createStatusItem() {
        let generation = UserDefaults.standard.integer(forKey: "statusItemGeneration")
        let autosaveName = "NotchTrayMain-\(generation)"
        // New status items insert leftmost — behind the expanded separator.
        // Seeding the preferred-position default (distance from the right
        // screen edge) before creation places the item on the visible side.
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(300, forKey: positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
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
    }

    /// If our own icon ended up left of the separator (hidden) or under the
    /// notch, recreate it under a fresh autosave identity — macOS assigns
    /// fresh items a new, visible position. No synthetic drags needed.
    private func rescueOwnIconIfHidden() async {
        guard let window = statusItem?.button?.window else { return }
        let frame = window.frame
        let notch = NotchMetrics.detect()
        let hidden = frame.minX < 0
            || (notch.map { frame.midX > $0.notchXRange.lowerBound
                    && frame.midX < $0.notchXRange.upperBound } ?? false)
        guard hidden else { return }
        DebugLog.log("rescue: recreating status item, old frame=\(frame)")
        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
        }
        let generation = UserDefaults.standard.integer(forKey: "statusItemGeneration") + 1
        UserDefaults.standard.set(generation, forKey: "statusItemGeneration")
        createStatusItem()
        updateBadge()
        DebugLog.log("rescue: new frame=\(String(describing: statusItem?.button?.window?.frame))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopPolling()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    func togglePanel() {
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
            onExit: {}
        )
    }

    private func notchHovered() {
        guard Prefs.openOnHover else { return }
        // Always respond to the hover; with nothing hidden the island shows
        // a brief "all visible" state instead of silently ignoring the user.
        panel?.show()
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
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
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

    @objc private func openSettings() {
        SettingsWindowController.show()
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
