import ApplicationServices
import Foundation

/// Waits for a status item's menu to close.
///
/// Revealing an off-screen item drags every hidden item back into the visible
/// menu bar, so the reveal has to be undone the moment the user is done with
/// the menu — too early and the menu is torn away from its anchor, too late and
/// the menu bar stays visibly scrambled for no reason. A fixed sleep is wrong
/// in both directions, so this listens for the real signal instead.
///
/// `kAXMenuClosedNotification` is the accurate one, but it only fires for apps
/// whose extras use a real `AXMenu`. Apps that draw their own dropdown window —
/// Electron-based ones especially — never post it, so the timeout is a required
/// fallback rather than a safety net.
///
/// `NSMenuDidEndTrackingNotification` is deliberately not used: it is posted on
/// the owning process's own notification centre and never crosses to us.
enum MenuMonitor {

    /// Resumes once the app's menu closes, or when `timeout` elapses.
    static func waitForMenuToClose(pid: pid_t, timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let waiter = MenuCloseWaiter(pid: pid, continuation: continuation)
                    waiter.start()
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            // Whichever lands first wins; the other is cancelled with the group.
            await group.next()
            group.cancelAll()
        }
    }
}

/// Bridges a single `AXObserver` callback into one continuation resume.
///
/// The observer keeps itself alive via `Unmanaged` while it is registered,
/// because AX hands the callback a raw pointer rather than a retained object.
private final class MenuCloseWaiter: @unchecked Sendable {
    private let pid: pid_t
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: AXObserver?
    private var selfReference: Unmanaged<MenuCloseWaiter>?
    private let lock = NSLock()

    init(pid: pid_t, continuation: CheckedContinuation<Void, Never>) {
        self.pid = pid
        self.continuation = continuation
    }

    func start() {
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<MenuCloseWaiter>.fromOpaque(refcon)
                .takeUnretainedValue()
                .finish()
        }

        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            finish()
            return
        }

        observer = created
        selfReference = Unmanaged.passRetained(self)
        let element = AXUIElementCreateApplication(pid)

        let added = AXObserverAddNotification(
            created,
            element,
            kAXMenuClosedNotification as CFString,
            selfReference!.toOpaque()
        )
        guard added == .success else {
            finish()
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )
    }

    /// Resumes the continuation exactly once and tears the observer down.
    /// The timeout branch and the notification can arrive together, so the
    /// nil-out is what makes the second one a no-op.
    func finish() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()

        guard pending != nil else { return }

        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
            AXObserverRemoveNotification(
                observer,
                AXUIElementCreateApplication(pid),
                kAXMenuClosedNotification as CFString
            )
            self.observer = nil
        }
        selfReference?.release()
        selfReference = nil

        pending?.resume()
    }
}
