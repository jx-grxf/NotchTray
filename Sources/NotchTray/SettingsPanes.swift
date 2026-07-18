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

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
        .onReceive(refreshTimer) { _ in
            axTrusted = AXIsProcessTrusted()
            screenRecording = CGPreflightScreenCaptureAccess()
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

// MARK: - About

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("NotchTray", value: AppVersion.displayString)
                Text("Shows menu bar items hidden behind the notch in a Dynamic Island-style panel. Hover the notch to open it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}
