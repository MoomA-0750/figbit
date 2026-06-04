import SwiftUI

struct ShortcutPanelView: View {
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(TabManager.self) private var tabManager

    @State private var isExpanded = false
    @State private var position: CGPoint = CGPoint(x: 0, y: 300)
    // ドラッグ開始時点の position を保持する（dragOffset を使わず position を直接更新する）
    @State private var dragStartPosition: CGPoint = .zero
    @State private var isDragging = false
    // 慣性用: 直近のドラッグサンプル（SwiftUIのvalue.velocityは静止直前の速度を反映しないため自前計算する）
    @State private var dragSamples: [(translation: CGSize, time: Date)] = []

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
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: tabWidth, height: tabHeight)
        .modifier(GlassTabStyle())
        .contentShape(Rectangle())
        .position(CGPoint(x: geo.size.width - tabWidth / 2 + 10, y: clampedY(geo)))
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartPosition = position
                        dragSamples.removeAll()
                    }
                    recordSample(value.translation)
                    // position を直接更新することで dragOffset の累積誤差をなくす
                    position.y = dragStartPosition.y + value.translation.height
                }
                .onEnded { value in
                    isDragging = false
                    let topBound    = tabHeight / 2 + 20
                    let bottomBound = geo.size.height - tabHeight / 2 - 20
                    // 境界内にスナップ（clamped表示値と一致させる）
                    position.y = min(max(position.y, topBound), bottomBound)

                    if value.translation.width < -30 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = true }
                    } else {
                        // 自前計算した離脱速度を使う（静止して離すとゼロになる）
                        let vy = releaseVelocity().height
                        let finalY = min(max(position.y + vy * 0.18, topBound), bottomBound)
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                            position.y = finalY
                        }
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
                .contentShape(Rectangle())
                .gesture(panelDragGesture(geo))
            shortcutGrid
        }
        .frame(width: panelWidth)
        .modifier(GlassPanelStyle())
        .position(clampedPanelPosition(geo))
        .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
    }

    // ドラッグはタイトルバー（ヘッダー）のみに付ける。グリッドを触っても動かない。
    // 座標空間は .global にする。ヘッダーは .position で動くパネルの子なので、.local だと
    // 移動した座標で translation が再計測されてフィードバックループ（震え・移動量の目減り）になる。
    private func panelDragGesture(_ geo: GeometryProxy) -> some Gesture {
        DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartPosition = position
                        dragSamples.removeAll()
                    }
                    recordSample(value.translation)
                    position = CGPoint(
                        x: dragStartPosition.x + value.translation.width,
                        y: dragStartPosition.y + value.translation.height
                    )
                }
                .onEnded { value in
                    isDragging = false
                    let leftClamp   = panelWidth  / 2 + 8
                    let rightClamp  = geo.size.width  - panelWidth  / 2 - 8
                    let topClamp    = panelHeight / 2 + 20
                    let bottomClamp = geo.size.height - panelHeight / 2 - 20

                    // 境界内にスナップ（clamped表示値と一致させる。視覚的変化なし）
                    position = CGPoint(
                        x: min(max(position.x, leftClamp), rightClamp),
                        y: min(max(position.y, topClamp),  bottomClamp)
                    )

                    // 収納判定: 速度ではなく translation / 開始位置で判定する
                    let rawX = dragStartPosition.x + value.translation.width
                    let isOffScreen        = rawX > geo.size.width - panelWidth / 2 + 20
                    let isExtraSwipeAtEdge = dragStartPosition.x >= rightClamp - 2 && value.translation.width >= 25

                    // 自前計算した離脱速度を使う（静止して離すとゼロになる）
                    let v = releaseVelocity()
                    let vx = v.width
                    let vy = v.height
                    let finalX = min(max(position.x + vx * 0.18, leftClamp),   rightClamp)
                    let finalY = min(max(position.y + vy * 0.18, topClamp),    bottomClamp)

                    if isOffScreen || isExtraSwipeAtEdge {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            position = CGPoint(x: position.x, y: finalY)
                            isExpanded = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                            position = CGPoint(x: finalX, y: finalY)
                        }
                    }
                }
    }

    private var panelHeader: some View {
        HStack {
            Text("ショートカット").font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = false }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
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

    // MARK: - Inertia velocity (self-computed)

    // ドラッグ中に呼び、直近のサンプルだけを保持する。
    private func recordSample(_ translation: CGSize) {
        let now = Date()
        dragSamples.append((translation, now))
        // 直近120ms分だけ残す（バッファ肥大を防ぐ）
        dragSamples.removeAll { now.timeIntervalSince($0.time) > 0.12 }
    }

    // 指を離した瞬間の速度（pt/s）を直近サンプルから算出する。
    // 静止してから離すと直近サンプルの移動量がゼロになり、速度もゼロになる。
    private func releaseVelocity() -> CGSize {
        defer { dragSamples.removeAll() }
        let now = Date()
        // 直近100ms以内のサンプルのみを使う
        let recent = dragSamples.filter { now.timeIntervalSince($0.time) < 0.1 }
        guard let first = recent.first, let last = recent.last else { return .zero }
        let dt = last.time.timeIntervalSince(first.time)
        guard dt > 0.001 else { return .zero }
        return CGSize(
            width:  (last.translation.width  - first.translation.width)  / dt,
            height: (last.translation.height - first.translation.height) / dt
        )
    }

    // MARK: - Helpers

    private func clampedY(_ geo: GeometryProxy) -> CGFloat {
        min(max(position.y, tabHeight / 2 + 20), geo.size.height - tabHeight / 2 - 20)
    }

    private func clampedPanelPosition(_ geo: GeometryProxy) -> CGPoint {
        CGPoint(
            x: min(max(position.x, panelWidth  / 2 + 8), geo.size.width  - panelWidth  / 2 - 8),
            y: min(max(position.y, panelHeight / 2 + 20), geo.size.height - panelHeight / 2 - 20)
        )
    }
}

struct ShortcutButtonView: View {
    let item: ShortcutItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let symbol = item.sfSymbol {
                    Image(systemName: symbol).font(.system(size: 14))
                } else {
                    Text(item.keyGlyph).font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                Text(LocalizedStringKey(item.label)).font(.system(size: 9)).lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .modifier(ShortcutButtonBackground())
        }
        .buttonStyle(PressEffectButtonStyle(pressedScale: 1.12, glowColor: .accentColor))
    }
}

// iOS 26では純正のインタラクティブなLiquid Glass、それ以前は半透明の塗り＋境界線。
private struct ShortcutButtonBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        } else {
            content
                .background(
                    Color(uiColor: .systemBackground).opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 0.5))
        }
    }
}

// MARK: - Adaptive Glass / Material Modifiers

private struct GlassTabStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.25), radius: 6, x: -2, y: 2)
        }
    }
}

private struct GlassPanelStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        }
    }
}
