import AppKit
import ApplicationServices

/// Waits for a status item's menu to close.
///
/// Revealing an off-screen item drags every hidden item back into the visible
/// menu bar, so the reveal has to be undone the moment the user is done with
/// the menu — too early and the menu is torn away from its anchor, too late and
/// the menu bar stays visibly scrambled for no reason.
///
/// Three signals race, because no single one is reliable:
///
/// - `kAXMenuClosedNotification` is the accurate one, but it only fires for
///   apps whose extras use a real `AXMenu`. Apps that draw their own dropdown
///   window — Electron-based ones especially — never post it.
/// - A global mouse-down is the pragmatic fallback: a click either picks
///   something in the menu or dismisses it, and both close it.
/// - A timeout is the last resort so a menu nobody interacts with cannot pin
///   the menu bar open indefinitely.
///
/// `NSMenuDidEndTrackingNotification` is deliberately unused: it is posted on
/// the owning process's own notification centre and never reaches us.
enum MenuMonitor {

    /// Resumes as soon as any of the three signals fires. Never hangs: every
    /// path funnels through the same single-shot resume.
    static func waitForMenuToClose(pid: pid_t, timeout: Duration) async {
        let waiter = MenuCloseWaiter(pid: pid)

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.begin(continuation: continuation, timeout: timeout)
            }
        } onCancel: {
            waiter.finish()
        }
    }
}

/// Bridges whichever signal arrives first into exactly one continuation resume.
///
/// The single-shot guarantee is the whole point: an earlier version raced the
/// observer against a timeout inside a task group, and cancelling the group
/// never resumed the observer's continuation, so the group waited on it
/// forever and the caller's move flow never completed.
private final class MenuCloseWaiter: @unchecked Sendable {
    private let pid: pid_t
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: AXObserver?
    private var selfReference: Unmanaged<MenuCloseWaiter>?
    private var timeoutTask: Task<Void, Never>?
    private var clickMonitor: Any?

    init(pid: pid_t) {
        self.pid = pid
    }

    func begin(continuation: CheckedContinuation<Void, Never>, timeout: Duration) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()

        armTimeout(timeout)
        armClickMonitor()
        armObserver()
    }

    private func armTimeout(_ timeout: Duration) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
        lock.lock()
        timeoutTask = task
        lock.unlock()
    }

    private func armClickMonitor() {
        // Global monitors only see events destined for other apps, which is
        // exactly the case here — the open menu belongs to the target app.
        let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.finish()
        }
        lock.lock()
        clickMonitor = monitor
        lock.unlock()
    }

    private func armObserver() {
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<MenuCloseWaiter>.fromOpaque(refcon)
                .takeUnretainedValue()
                .finish()
        }

        guard AXObserverCreate(pid, callback, &created) == .success,
              let created else { return }

        let reference = Unmanaged.passRetained(self)
        let element = AXUIElementCreateApplication(pid)

        guard AXObserverAddNotification(
            created,
            element,
            kAXMenuClosedNotification as CFString,
            reference.toOpaque()
        ) == .success else {
            reference.release()
            return
        }

        lock.lock()
        observer = created
        selfReference = reference
        lock.unlock()

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )
    }

    /// Resumes the continuation exactly once and tears everything down.
    /// Safe to call from any thread and any number of times; only the first
    /// call does anything.
    func finish() {
        lock.lock()
        guard let pending = continuation else {
            lock.unlock()
            return
        }
        continuation = nil

        let observer = self.observer
        let reference = selfReference
        let monitor = clickMonitor
        let timeout = timeoutTask
        self.observer = nil
        selfReference = nil
        clickMonitor = nil
        timeoutTask = nil
        lock.unlock()

        timeout?.cancel()

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
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        reference?.release()

        pending.resume()
    }
}
