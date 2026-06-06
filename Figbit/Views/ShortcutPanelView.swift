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
            .onReceive(NotificationCenter.default.publisher(for: .figbitPencilAction)) { note in
                guard let windowLoc = note.userInfo?["windowLocation"] as? CGPoint else { return }
                // geo.frame(in: .global) はSwiftUIのグローバル座標系（= UIWindow座標）のオリジンを返す。
                // ウィンドウ座標からGeometryReaderのローカル座標に変換する。
                let geoOrigin = geo.frame(in: .global).origin
                let localLoc = CGPoint(x: windowLoc.x - geoOrigin.x, y: windowLoc.y - geoOrigin.y)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isExpanded {
                        isExpanded = false
                    } else {
                        position = localLoc
                        isExpanded = true
                    }
                }
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
        // パネル全体（ボタン以外の余白・背景含む）を確実なヒット領域にして、
        // タップ／ホバーが背後のWebViewへ抜けないようにする。WebViewはペン追跡用の
        // ホバー認識器を持つため、パネルが全種別で領域を主張しないとボタンまでホバーが
        // 届かない（=ホバー無反応になる）。.position より前に置く点も重要
        // （後ろだとフレームが親全体に広がり画面全体を奪う）。
        .contentShape(Rectangle())
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
                if item.kind == .modifierHold, !item.modifiers.isEmpty {
                    ShortcutButtonView(
                        item: item,
                        action: {},
                        onPress: { item.modifiers.forEach { tabManager.activeTab?.webView.activateModifier($0) } },
                        onRelease: { item.modifiers.forEach { tabManager.activeTab?.webView.deactivateModifier($0) } }
                    )
                } else {
                    ShortcutButtonView(item: item, action: {
                        tabManager.activeTab?.webView.send(shortcut: item)
                    })
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
    var onPress: (() -> Void)? = nil
    var onRelease: (() -> Void)? = nil

    // Apple Pencil / ポインタのホバー状態。ボタン全面で検出するため .onHover を使う
    // （純正 .hoverEffect はPencilだと不透明な中身の上でしか安定発火しないため）。
    @State private var isHovering = false
    // modifier-hold 専用の状態
    @State private var isSticky = false
    @State private var isHeld = false
    @State private var pressStartTime: Date = .distantPast
    // 直近の「クイックタップ」を離した時刻。長押し（物理ホールド）では更新しない。
    @State private var lastTapTime: Date = .distantPast
    // 今回の押下でスティッキーをトグルしたか（トグル時はタップ記録しない）。
    @State private var didToggleStickyThisPress = false

    private var isActive: Bool { isSticky || isHeld }

    var body: some View {
        if item.kind == .modifierHold {
            modifierHoldButton
        } else {
            regularButton
        }
    }

    private var regularButton: some View {
        Button(action: action) {
            buttonLabel
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .modifier(ShortcutButtonBackground())
        }
        .buttonStyle(PressEffectButtonStyle(pressedScale: 1.12, glowColor: .accentColor))
        // 純正 .lift 風の持ち上がり（位置移動なし＝チラつかない）。ボタン全面で反応。
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .brightness(isHovering ? 0.04 : 0)
        .shadow(color: .black.opacity(isHovering ? 0.28 : 0), radius: isHovering ? 8 : 0, y: isHovering ? 3 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovering)
        .onHover { isHovering = $0 }
    }

    // 物理ホールド中はボタンが拡大。ダブルタップでスティッキー（ハイライト持続）。
    private var modifierHoldButton: some View {
        buttonLabel
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .modifier(ShortcutButtonBackground(isActive: isActive))
            .scaleEffect(isHeld ? 1.12 : (isHovering ? 1.05 : 1.0))
            .brightness(isHovering && !isActive ? 0.04 : 0)
            .shadow(color: .black.opacity(isHovering && !isHeld ? 0.28 : 0), radius: isHovering && !isHeld ? 8 : 0, y: isHovering && !isHeld ? 3 : 0)
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isHeld)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovering)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            // DragGesture(minimumDistance:0) は静止押しで onChanged が発火しないことがあるため、
            // 静止押しでも確実に press/release を取れる onLongPressGesture(pressing:) を使う。
            // maximumDistance: .infinity でホールド中に指がボタン外へずれてもキャンセルしない。
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                if pressing { handlePress() } else { handleRelease() }
            }, perform: {})
            .onDisappear {
                // パネルが閉じた時などにアクティブなままにならないようクリーンアップ
                if isActive { onRelease?() }
                isHeld = false
                isSticky = false
                isHovering = false
                lastTapTime = .distantPast
                didToggleStickyThisPress = false
            }
    }

    @ViewBuilder
    private var buttonLabel: some View {
        VStack(spacing: 2) {
            if let symbol = item.sfSymbol {
                Image(systemName: symbol).font(.system(size: 14))
            } else {
                Text(item.keyGlyph).font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            Text(LocalizedStringKey(item.label)).font(.system(size: 9)).lineLimit(1)
        }
    }

    private func handlePress() {
        guard !isHeld else { return }
        let wasActive = isActive
        let now = Date()
        pressStartTime = now
        isHeld = true
        // 直前が「クイックタップ」で、その離上から350ms以内の押下ならダブルタップ → スティッキーをトグル。
        // 長押し（物理ホールド）はタップとして記録されないため、連続ホールドで誤トグルしない。
        if now.timeIntervalSince(lastTapTime) < 0.35 {
            isSticky.toggle()
            lastTapTime = .distantPast
            didToggleStickyThisPress = true
        } else {
            didToggleStickyThisPress = false
        }
        if !wasActive && isActive { onPress?() }
        if wasActive && !isActive { onRelease?() }
    }

    private func handleRelease() {
        let wasActive = isActive
        isHeld = false
        let now = Date()
        // スティッキートグルではなく、短時間で離されたら「クイックタップ」として記録する。
        // 長押しは記録しないので、次のホールドが誤ってダブルタップ扱いされない。
        if !didToggleStickyThisPress, now.timeIntervalSince(pressStartTime) < 0.25 {
            lastTapTime = now
        } else {
            lastTapTime = .distantPast
        }
        if wasActive && !isActive { onRelease?() }
    }
}

// iOS 26では純正のインタラクティブなLiquid Glass、それ以前は半透明の塗り＋境界線。
// isActive=true の時はアクセントカラーでハイライトする。
private struct ShortcutButtonBackground: ViewModifier {
    var isActive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor.opacity(0.3) : .clear)
                )
        } else {
            content
                .background(
                    isActive ? Color.accentColor.opacity(0.25) : Color(uiColor: .systemBackground).opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                    isActive ? Color.accentColor : Color(.separator),
                    lineWidth: isActive ? 1.0 : 0.5
                ))
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
