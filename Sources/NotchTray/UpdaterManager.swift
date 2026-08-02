import Foundation
import Observation
import Sparkle

/// Which release track the app follows.
///
/// Sparkle models this as a single feed where prerelease items carry a
/// `<sparkle:channel>` element. Subscribers to the default channel never see
/// them; subscribers to `beta` see both, because Sparkle always includes the
/// default channel alongside whatever `allowedChannels` returns.
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        }
    }

    var detail: String {
        switch self {
        case .stable: "Only released versions."
        case .beta: "Prereleases too — earlier features, rougher edges."
        }
    }

    /// Channel names handed to Sparkle. Stable subscribes to nothing extra;
    /// the default channel is always included by the updater itself.
    var sparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .beta: ["beta"]
        }
    }
}

/// Owns the Sparkle updater and exposes its state to SwiftUI.
///
/// `SPUStandardUpdaterController` is created eagerly so the scheduled check
/// starts on launch, and the delegate is what actually gates prereleases.
@MainActor
@Observable
final class UpdaterManager: NSObject {
    static let shared = UpdaterManager()

    /// Mirrors Sparkle's own state so the settings UI can disable the button
    /// while a check is already running.
    private(set) var canCheckForUpdates = false

    var channel: UpdateChannel {
        didSet {
            guard channel != oldValue else { return }
            UserDefaults.standard.set(channel.rawValue, forKey: Prefs.updateChannelKey)
            // The feed is unchanged; only the channel filter moved. Re-check so
            // switching to beta surfaces a waiting prerelease immediately
            // instead of at the next scheduled interval.
            updater.checkForUpdatesInBackground()
        }
    }

    var automaticallyChecksForUpdates: Bool {
        didSet { updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    var automaticallyDownloadsUpdates: Bool {
        didSet { updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }

    private let controller: SPUStandardUpdaterController
    private let updaterDelegate = UpdaterDelegate()
    private var canCheckObservation: NSKeyValueObservation?

    private var updater: SPUUpdater { controller.updater }

    /// Marketing version and build, for display in settings.
    var currentVersion: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    private override init() {
        channel = UpdateChannel(
            rawValue: UserDefaults.standard.string(forKey: Prefs.updateChannelKey) ?? ""
        ) ?? .stable

        // The delegate cannot be assigned after construction, so it is a
        // standalone object handed in here. `startingUpdater: true` lets the
        // controller start the updater itself, with the channel filter already
        // in place before the first scheduled check.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )

        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates

        super.init()

        canCheckForUpdates = controller.updater.canCheckForUpdates
        // Read the new value out of the KVO change rather than off the updater:
        // Sparkle isolates its properties to the main actor, and this closure
        // is not isolated.
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates, options: [.initial, .new]
        ) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    /// User-initiated check; shows Sparkle's standard UI including "you're up
    /// to date", which the background check deliberately suppresses.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

/// Sparkle's delegate. Kept separate from `UpdaterManager` because
/// `SPUStandardUpdaterController` takes its delegate at construction, before
/// `self` exists, and because the channel decision only needs a defaults read.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: Prefs.updateChannelKey) ?? ""
        return (UpdateChannel(rawValue: raw) ?? .stable).sparkleChannels
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        DebugLog.log("updater: loaded appcast with \(appcast.items.count) items")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Sparkle reports "no update found" as an abort; that is routine, so
        // it is logged rather than surfaced.
        DebugLog.log("updater: aborted — \(error.localizedDescription)")
    }
}
