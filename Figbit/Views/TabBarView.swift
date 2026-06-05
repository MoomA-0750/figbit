import SwiftUI

// [(ホーム)          (タブストリップ)          (歯車)]
// ホームボタンはタブが増える前から常に存在し、ホーム画面を表示する。
// タブストリップはファイルタブの一覧。タブが0枚のときは非表示。
struct TabToolbar: ToolbarContent {
    var tabManager: TabManager
    @Binding var showSettings: Bool
    @Binding var showingHome: Bool
    var windowWidth: CGFloat

    var body: some ToolbarContent {
        // ホームボタン（一番左）
        ToolbarItem(placement: .topBarLeading) {
            Button { showingHome = true } label: {
                Image(systemName: showingHome ? "house.fill" : "house")
            }
        }

        // タブストリップ（中央）
        ToolbarItem(placement: .principal) {
            if !tabManager.tabs.isEmpty {
                TabStrip(
                    tabManager: tabManager,
                    windowWidth: windowWidth,
                    showingHome: showingHome,
                    closeHome: { showingHome = false }
                )
            }
        }

        // 歯車（右）
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}

// MARK: - Tab Strip (Safari風のグループ背景)

struct WindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TabStrip: View {
    var tabManager: TabManager
    var windowWidth: CGFloat
    // ホーム表示中はどのタブもアクティブに見せない（紛らわしいため）。
    var showingHome: Bool = false
    // タブチップがタップされたときにホームを閉じるコールバック
    var closeHome: () -> Void = {}
    @State private var contentWidth: CGFloat = 0

    // 左のホームボタン＋右の＋/歯車＋余白のおおよその予約幅
    private let reservedWidth: CGFloat = 280

    var body: some View {
        let cap = windowWidth > reservedWidth ? windowWidth - reservedWidth : .greatestFiniteMagnitude
        let stripWidth = contentWidth > 0 ? min(contentWidth, cap) : nil

        ScrollView(.horizontal, showsIndicators: false) {
            tabRow
        }
        .frame(width: stripWidth)
        .clipShape(Capsule())
        .modifier(TabGroupBackground())
        .background(measuringProbe)
        .onPreferenceChange(ContentWidthKey.self) { contentWidth = $0 }
        // カプセル背景の幅もタブ数の増減に合わせてなめらかに伸縮させる。
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: tabManager.tabs.count)
    }

    private var measuringProbe: some View {
        tabRow
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { inner in
                    Color.clear.preference(key: ContentWidthKey.self, value: inner.size.width)
                }
            )
            .hidden()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var tabRow: some View {
        let stack = HStack(spacing: 6) {
            ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                TabChip(
                    tab: tab,
                    isActive: !showingHome && index == tabManager.activeIndex,
                    onSelect: {
                        tabManager.selectTab(at: index)
                        closeHome()          // タブを選んだらホームを閉じる
                    },
                    onClose: {
                        // 閉じるボタン自身が起点だと暗黙アニメが除去トランジションを取りこぼすため明示的に包む。
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            tabManager.closeTab(at: index)
                        }
                    }
                )
                // タブの追加/削除時にチップがスケール＋フェードで出入りする。
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(5)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: tabManager.tabs.count)

        if #available(iOS 26, *) {
            GlassEffectContainer { stack }
        } else {
            stack
        }
    }
}

// グループ背景: iOS 26はガラス、それ以前は薄いマテリアル。
private struct TabGroupBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
    }
}

// MARK: - Tab Chip

private struct TabChip: View {
    static let height: CGFloat = 33
    static let titleWidth: CGFloat = 120

    var tab: FigmaTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Image(systemName: tab.kind.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 16)

                Text(tab.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.7)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: TabChip.titleWidth, alignment: .leading)

                if tab.isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                } else {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: TabChip.height)
            .modifier(TabChipStyle(isActive: isActive))
        }
        .buttonStyle(PressEffectButtonStyle(pressedScale: 1.06))
    }
}

// MARK: - Style Modifier

private struct TabChipStyle: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isActive {
                content.glassEffect(.regular.tint(Color.white.opacity(0.28)).interactive(), in: Capsule())
            } else {
                content.clipShape(Capsule())
            }
        } else {
            content
                .background(isActive ? Color.primary.opacity(0.18) : .clear, in: Capsule())
                .overlay(Capsule().stroke(isActive ? Color.primary.opacity(0.25) : .clear, lineWidth: 1))
        }
    }
}
