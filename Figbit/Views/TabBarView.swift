import SwiftUI

struct TabBarView: View {
    var tabManager: TabManager
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabChip(
                            tab: tab,
                            isActive: index == tabManager.activeIndex,
                            onSelect: { tabManager.selectTab(at: index) },
                            onClose: { tabManager.closeTab(at: index) }
                        )
                    }

                    Button(action: { tabManager.addTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }

            Divider().frame(height: 24).padding(.horizontal, 4)

            HStack(spacing: 2) {
                NavButton(symbol: "chevron.left", enabled: tabManager.activeTab?.canGoBack == true) {
                    tabManager.goBack()
                }
                NavButton(symbol: "chevron.right", enabled: tabManager.activeTab?.canGoForward == true) {
                    tabManager.goForward()
                }
                NavButton(
                    symbol: tabManager.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise",
                    enabled: true
                ) {
                    tabManager.reload()
                }
            }

            Divider().frame(height: 24).padding(.horizontal, 4)

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TabChip: View {
    var tab: FigmaTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text(tab.title)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                if tab.isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                } else {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isActive ? Color(uiColor: .systemBackground) : Color(uiColor: .systemBackground).opacity(0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct NavButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
