import AppKit
import ServiceManagement
import SwiftUI

// MARK: - General

struct GeneralSettingsPane: View {
    @AppStorage(Prefs.openOnHoverKey) private var openOnHover = true
    @AppStorage(Prefs.autoCloseDelayKey) private var autoCloseDelay = 0.6
    @AppStorage(Prefs.showInDockKey) private var showInDock = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                        Text("Start NotchTray automatically when you log in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

                Toggle(isOn: $showInDock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in Dock")
                        Text("Off: NotchTray lives only in the menu bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: showInDock) { _, _ in
                    if Prefs.showInDock {
                        NSApp.setActivationPolicy(.regular)
                    } else {
                        // Apply instantly; re-front the settings window since
                        // the policy flip deactivates the app.
                        NSApp.setActivationPolicy(.accessory)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.activate(ignoringOtherApps: true)
                            NSApp.windows.first { $0.title == "Settings" }?
                                .makeKeyAndOrderFront(nil)
                        }
                    }
                }
            }

            Section("Island") {
                Toggle(isOn: $openOnHover) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open when hovering the notch")
                        Text("Off: use the menu bar icon or ⌃⌥N instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                LabeledContent("Auto-close delay") {
                    HStack(spacing: 12) {
                        Slider(value: $autoCloseDelay, in: 0.3...2.0, step: 0.1)
                            .frame(width: 180)
                        Text(String(format: "%.1f s", autoCloseDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

// MARK: - Permissions

struct PermissionsSettingsPane: View {
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section("Required") {
                permissionRow(
                    title: "Accessibility",
                    detail: "Reads menu bar items and activates them.",
                    granted: axTrusted,
                    pane: "Privacy_Accessibility"
                )
            }
            Section("Optional") {
                permissionRow(
                    title: "Screen Recording",
                    detail: "Shows the real menu bar icons instead of app icons.",
                    granted: screenRecording,
                    pane: "Privacy_ScreenCapture"
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        // Bound to the view's lifetime. A `Timer.publish` stored in a plain
        // `let` would be rebuilt every time SwiftUI re-initialises this struct,
        // spinning up a fresh timer on each unrelated parent re-render.
        .task {
            while !Task.isCancelled {
                axTrusted = AXIsProcessTrusted()
                screenRecording = CGPreflightScreenCaptureAccess()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, pane: String) -> some View {
        LabeledContent {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Open System Settings…") {
                    let url = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
                    if let url = URL(string: url) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Updates

struct UpdatesSettingsPane: View {
    @Bindable private var updater = UpdaterManager.shared

    var body: some View {
        Form {
            Section {
                Picker("Channel", selection: $updater.channel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                .pickerStyle(.segmented)

                Text(updater.channel.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Release channel")
            }

            Section("Automatic updates") {
                Toggle(isOn: $updater.automaticallyChecksForUpdates) {
                    Text("Check for updates automatically")
                    Text("Once a day, in the background.")
                }
                .toggleStyle(.switch)

                Toggle(isOn: $updater.automaticallyDownloadsUpdates) {
                    Text("Download updates automatically")
                    Text("Installs on the next launch instead of asking first.")
                }
                .toggleStyle(.switch)
                .disabled(!updater.automaticallyChecksForUpdates)
            }

            Section {
                LabeledContent("Installed version", value: updater.currentVersion)
                LabeledContent("Last checked") {
                    if let date = updater.lastUpdateCheckDate {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("Never").foregroundStyle(.secondary)
                    }
                }
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    private static let repository = URL(string: "https://github.com/jx-grxf/NotchTray")!
    private static let issues = URL(string: "https://github.com/jx-grxf/NotchTray/issues/new")!
    private static let license = URL(string: "https://github.com/jx-grxf/NotchTray/blob/main/LICENSE")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NotchTray")
                            .font(.title2.weight(.semibold))
                        Text("Version \(AppVersion.displayString)")
                            .foregroundStyle(.secondary)
                        Text("by Johannes Grof")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                Text("Shows menu bar items hidden behind the notch in a Dynamic Island-style panel. Hover the notch to open it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: Self.repository) {
                    Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.issues) {
                    Label("Report a bug", systemImage: "ladybug")
                }
                Link(destination: Self.license) {
                    Label("MIT License", systemImage: "doc.text")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}
