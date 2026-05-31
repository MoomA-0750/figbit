import SwiftUI

struct ShortcutPanelView: View {
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(TabManager.self) private var tabManager

    @State private var isExpanded = false
    @State private var position: CGPoint = CGPoint(x: 0, y: 300)
    @State private var dragOffset: CGSize = .zero

    private let panelWidth: CGFloat = 200
    private let panelHeight: CGFloat = 280
    private let tabWidth: CGFloat = 28
    private let tabHeight: CGFloat = 72

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isExpanded {
                    expandedPanel(geo: geo)
                } else {
                    collapsedTab(geo: geo)
                }
            }
            .onAppear {
                position = CGPoint(x: geo.size.width - panelWidth / 2 - 8, y: geo.size.height * 0.4)
            }
        }
    }

    // MARK: - Collapsed Tab

    private func collapsedTab(geo: GeometryProxy) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: tabWidth, height: tabHeight)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, x: -2, y: 2)
        .position(CGPoint(x: geo.size.width - tabWidth / 2 + 10, y: clampedY(geo)))
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in dragOffset = value.translation }
                .onEnded { value in
                    let newY = clampedY(geo) + value.translation.height
                    position.y = min(max(newY, tabHeight / 2 + 20), geo.size.height - tabHeight / 2 - 20)
                    dragOffset = .zero
                    if value.translation.width < -30 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = true }
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = true }
        }
    }

    // MARK: - Expanded Panel

    private func expandedPanel(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            shortcutGrid
        }
        .frame(width: panelWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .position(clampedPanelPosition(geo))
        .gesture(
            DragGesture()
                .onChanged { value in dragOffset = value.translation }
                .onEnded { value in
                    let p = clampedPanelPosition(geo)
                    let newX = p.x + value.translation.width
                    let newY = p.y + value.translation.height
                    position = CGPoint(
                        x: min(max(newX, panelWidth / 2 + 8), geo.size.width - panelWidth / 2 - 8),
                        y: min(max(newY, panelHeight / 2 + 20), geo.size.height - panelHeight / 2 - 20)
                    )
                    dragOffset = .zero
                    if position.x > geo.size.width - panelWidth / 2 - 40 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = false }
                    }
                }
        )
        .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
    }

    private var panelHeader: some View {
        HStack {
            Image(systemName: "bolt.fill").foregroundStyle(Color.accentColor).font(.system(size: 13))
            Text("ショートカット").font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = false }
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var shortcutGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(shortcutSync.shortcuts) { item in
                ShortcutButtonView(item: item) {
                    tabManager.activeTab?.webView.send(shortcut: item)
                }
            }
        }
        .padding(8)
    }

    // MARK: - Helpers

    private func clampedY(_ geo: GeometryProxy) -> CGFloat {
        let base = position.y + dragOffset.height
        return min(max(base, tabHeight / 2 + 20), geo.size.height - tabHeight / 2 - 20)
    }

    private func clampedPanelPosition(_ geo: GeometryProxy) -> CGPoint {
        let x = min(max(position.x + dragOffset.width, panelWidth / 2 + 8), geo.size.width - panelWidth / 2 - 8)
        let y = min(max(position.y + dragOffset.height, panelHeight / 2 + 20), geo.size.height - panelHeight / 2 - 20)
        return CGPoint(x: x, y: y)
    }
}

struct ShortcutButtonView: View {
    let item: ShortcutItem
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.08)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.08)) { isPressed = false }
            }
            action()
        } label: {
            VStack(spacing: 2) {
                if let symbol = item.sfSymbol {
                    Image(systemName: symbol).font(.system(size: 14))
                } else {
                    Text(item.key.uppercased()).font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                Text(item.label).font(.system(size: 9)).lineLimit(1)
            }
            .foregroundStyle(isPressed ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                isPressed ? Color.accentColor : Color(uiColor: .systemBackground).opacity(0.8),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1.0)
    }
}
