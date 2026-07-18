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

    private var iconStrip: some View {
        HStack(spacing: 4) {
            ForEach(store.hiddenItems) { item in
                IconCell(item: item, capture: store.captures[item.id]) {
                    store.activate(item)
                    onClose()
                }
            }
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
            MiniControl(symbol: "gearshape.fill", help: "Settings") {
                onClose()
                SettingsWindowController.show()
            }
            MiniControl(symbol: "power", help: "Quit NotchTray") {
                NSApp.terminate(nil)
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
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? .white : .gray)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Color.white.opacity(0.15) : .clear))
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
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            iconImage
                .frame(height: 24)
                .frame(minWidth: 30)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.detail.isEmpty ? item.appName : "\(item.appName) — \(item.detail)")
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
