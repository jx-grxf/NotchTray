import SwiftUI

/// The notch island. Collapsed it matches the hardware notch exactly
/// (solid black, invisible against it); expanded it reveals the hidden
/// status items as a horizontal strip of their real menu bar icons.
struct OverflowView: View {
    let store: MenuBarStore
    var onHover: (Bool) -> Void
    var onClose: () -> Void

    private var notchWidth: CGFloat { store.metrics?.notchWidth ?? 200 }
    private var menuBarHeight: CGFloat { store.metrics?.menuBarHeight ?? 38 }

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        VStack(spacing: 0) {
            // Dead zone behind the physical notch.
            Color.clear.frame(height: menuBarHeight)

            content
                .opacity(store.panelExpanded ? 1 : 0)
        }
        .frame(width: store.panelExpanded ? nil : notchWidth)
        .frame(height: store.panelExpanded ? nil : menuBarHeight, alignment: .top)
        .background(NotchShape(topCornerRadius: 12, bottomCornerRadius: 18).fill(.black))
        .clipShape(NotchShape(topCornerRadius: 12, bottomCornerRadius: 18))
        .shadow(color: .black.opacity(store.panelExpanded ? 0.55 : 0), radius: 16, y: 8)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: store.panelExpanded)
        .onHover(perform: onHover)
    }

    @ViewBuilder
    private var content: some View {
        if !store.axTrusted {
            accessibilityPrompt
        } else if store.hiddenItems.isEmpty {
            Text("All status items are visible")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 14)
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 12)
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
                .frame(height: 22)
                .frame(minWidth: 26)
                .padding(.horizontal, 3)
                .padding(.vertical, 5)
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
