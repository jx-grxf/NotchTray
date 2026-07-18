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
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = OverflowPanel(store: store)

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
        store.startPolling()
        registerHotKey()

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
        panel?.toggle()
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
