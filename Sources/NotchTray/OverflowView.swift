import SwiftUI

/// The notch island. Collapsed it matches the hardware notch exactly
/// (solid black, invisible against it); expanded it reveals the hidden
/// status items as a horizontal strip of their real menu bar icons.
struct OverflowView: View {
    let store: MenuBarStore
    var onClose: () -> Void = {}

    private var notchWidth: CGFloat { store.metrics?.notchWidth ?? 200 }
    private var menuBarHeight: CGFloat { store.metrics?.menuBarHeight ?? 38 }

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        content
            .opacity(store.panelExpanded ? 1 : 0)
            // Dead zone behind the physical notch; padding (not a spacer)
            // so the island hugs its content horizontally.
            .padding(.top, menuBarHeight)
            .frame(minWidth: notchWidth + 36)
            .frame(width: store.panelExpanded ? nil : notchWidth)
        .frame(height: store.panelExpanded ? nil : menuBarHeight, alignment: .top)
        .background(NotchShape(topCornerRadius: 12, bottomCornerRadius: 18).fill(.black))
        .clipShape(NotchShape(topCornerRadius: 12, bottomCornerRadius: 18))
        .shadow(color: .black.opacity(store.panelExpanded ? 0.55 : 0), radius: 16, y: 8)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: store.panelExpanded)
    }

    @ViewBuilder
    private var content: some View {
        if !store.axTrusted {
            accessibilityPrompt
        } else if store.editMode {
            editStrip
        } else if store.hiddenItems.isEmpty {
            HStack(spacing: 4) {
                Text("All status items are visible")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                divider
                controlButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, 12)
        } else {
            iconStrip
        }
    }

    /// Widest the icon run may grow before it starts scrolling. The panel is a
    /// fixed 640pt window, and the divider plus the control buttons have to
    /// stay inside it — without this bound a long run of hidden items pushes
    /// Edit/Settings/Quit past the window edge, where they are both invisible
    /// and unclickable.
    private static let maxIconRunWidth: CGFloat = 460

    /// An `IconCell` is 30pt minimum plus 4pt padding either side, and the
    /// enclosing `HStack` adds 4pt of spacing per item.
    private static let iconCellWidth: CGFloat = 42

    private var iconRunWidth: CGFloat {
        min(CGFloat(store.hiddenItems.count) * Self.iconCellWidth, Self.maxIconRunWidth)
    }

    private var iconStrip: some View {
        HStack(spacing: 4) {
            // Scrolls only once the run actually outgrows the bound; below it
            // the explicit width keeps the island hugging its content.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.hiddenItems) { item in
                        IconCell(
                            item: item,
                            capture: store.captures[item.id],
                            busy: store.activatingItemID == item.id
                        ) {
                            // Deliberately no onClose(): revealing the item
                            // takes a couple of seconds, and tearing the island
                            // down first is what made the icon look like it was
                            // in two places at once. The island stays anchored
                            // and marks the item busy until the flow finishes.
                            store.activate(item)
                        }
                    }
                }
            }
            .frame(width: iconRunWidth)
            divider
            controlButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private var controlButtons: some View {
        HStack(spacing: 2) {
            MiniControl(
                symbol: store.editMode ? "checkmark" : "pencil",
                help: store.editMode ? "Done" : "Choose items to hide in the notch",
                active: store.editMode
            ) {
                store.editMode.toggle()
                if store.editMode {
                    Task { await store.captureIcons() }
                }
            }
            MiniControl(symbol: "gearshape.fill", help: "Settings") {
                onClose()
                SettingsWindowController.show()
            }
            MiniControl(symbol: "power", help: "Quit NotchTray") {
                NSApp.terminate(nil)
            }
        }
    }

    /// Edit mode: every item becomes a hide/restore toggle.
    private var editStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !store.hiddenItems.isEmpty {
                caption("In the notch — click to restore")
                itemRow(store.hiddenItems) { store.restoreFromNotch($0) }
            }
            caption("Menu bar — click to hide in the notch")
            ScrollView(.horizontal, showsIndicators: false) {
                itemRow(store.visibleItems) { store.hideIntoNotch($0) }
            }
            .frame(maxWidth: 460)

            HStack(spacing: 4) {
                Spacer()
                if store.isMoving {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                divider
                controlButtons
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.gray)
            .padding(.leading, 4)
    }

    private func itemRow(_ items: [MenuBarItem], action: @escaping (MenuBarItem) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                IconCell(item: item, capture: store.captures[item.id]) {
                    action(item)
                }
                .disabled(store.isMoving)
            }
        }
    }

    private var accessibilityPrompt: some View {
        VStack(spacing: 8) {
            Text("NotchTray needs Accessibility access\nto read menu bar items.")
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Grant access…") {
                store.requestAccessibility()
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

/// Tiny gray utility button (settings gear, power switch) inside the island.
private struct MiniControl: View {
    let symbol: String
    let help: String
    var active: Bool = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active || hovering ? .white : .gray)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        active ? Color.white.opacity(0.25)
                            : hovering ? Color.white.opacity(0.15)
                            : .clear
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// One hidden status item, rendered with its real captured menu bar icon
/// when available, falling back to the owning app's icon.
private struct IconCell: View {
    let item: MenuBarItem
    let capture: CGImage?
    /// The item is being revealed and pressed right now.
    var busy = false
    var action: () -> Void
    @State private var hovering = false

    private var label: String {
        item.detail.isEmpty ? item.appName : "\(item.appName) — \(item.detail)"
    }

    var body: some View {
        Button(action: action) {
            iconImage
                .frame(height: 24)
                // Captured items carry their rendered width — a "Now Playing"
                // or battery-percentage tile is far wider than a glyph, and
                // without a ceiling one of them would push the controls out of
                // the panel.
                .frame(minWidth: 30, maxWidth: 80)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .opacity(busy ? 0.35 : 1)
                .overlay {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering && !busy ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
        .help(label)
        // The icons are decorative images, so the button would otherwise be
        // announced as unlabelled.
        .accessibilityLabel(label)
        .accessibilityHint(busy ? "Opening" : "Opens this status item")
    }

    @ViewBuilder
    private var iconImage: some View {
        if let capture {
            Image(decorative: capture, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(.white)
        }
    }
}
