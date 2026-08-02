import AppKit

/// A main-actor snapshot of the running applications a scan needs.
///
/// `MenuBarScanner.scan` runs detached, because Accessibility calls can block
/// on an unresponsive process. The AX calls themselves are documented as
/// thread-safe CF calls, but `NSWorkspace` and `NSRunningApplication` are not —
/// and `NSRunningApplication.icon` in particular materialises an `NSImage`
/// lazily on first access. Reading all of that here, on the main actor, keeps
/// the detached work to the part that is actually safe to run off-main.
struct RunningAppSnapshot: Sendable {
    let pid: pid_t
    let name: String
    /// Stable across launches, unlike the pid — used to key the icon cache.
    let bundleID: String
    /// Materialised on the main actor and never mutated afterwards.
    let icon: NSImage?

    @MainActor
    static func current() -> [RunningAppSnapshot] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid != ownPID, pid > 0 else { return nil }
            return RunningAppSnapshot(
                pid: pid,
                name: app.localizedName ?? "PID \(pid)",
                bundleID: app.bundleIdentifier ?? "pid.\(pid)",
                icon: app.icon
            )
        }
    }
}
