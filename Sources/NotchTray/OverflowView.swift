import SwiftUI

/// Content of the drop-down: hidden status items as clickable rows on a
/// solid black Dynamic Island-style shape that blends with the notch.
struct OverflowView: View {
    let store: MenuBarStore
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Dead zone behind the physical notch; content starts below it.
            Color.clear
                .frame(height: store.metrics?.menuBarHeight ?? 38)

            header

            Group {
                if !store.axTrusted {
                    accessibilityPrompt
                } else if store.hiddenItems.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .padding(.horizontal, 10)

            footer
        }
        .frame(width: OverflowPanel.contentWidth)
        .background(NotchShape(topCornerRadius: 12, bottomCornerRadius: 18).fill(.black))
        .clipShape(NotchShape(topCornerRadius: 12, bottomCornerRadius: 18))
    }

    private var header: some View {
        HStack {
            Text("Hidden menu bar items")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.gray)
            Spacer()
            if store.axTrusted {
                Text("\(store.hiddenItems.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.85)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(store.hiddenItems) { item in
                    ItemRow(item: item) {
                        store.activate(item)
                        onClose()
                    }
                }
            }
        }
        .frame(maxHeight: 420)
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text("All status items are visible")
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var accessibilityPrompt: some View {
        VStack(spacing: 8) {
            Text("NotchTray needs Accessibility access to read menu bar items.")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Grant access…") {
                store.requestAccessibility()
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text("⌃⌥N to toggle")
                .font(.system(size: 10))
                .foregroundStyle(.gray)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}

private struct ItemRow: View {
    let item: MenuBarItem
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(item.appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: item.visibility == .behindNotch
                      ? "eye.slash"
                      : "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.white.opacity(0.12) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
