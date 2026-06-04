import SwiftUI

// iPadのタイトル帯（信号機の列）に、システムのツールバーとしてタブと操作ボタンを配置する。
// OSが信号機と上下位置を自動で揃えるため、手動のオフセットやsafeArea潜り込ませは不要。
// 右端の＋/歯車は純正のツールバーボタンなので、iOS 26では自動でLiquid Glass＋純正の押下挙動になる。
struct TabToolbar: ToolbarContent {
    var tabManager: TabManager
    @Binding var showSettings: Bool
    var windowWidth: CGFloat

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            TabStrip(tabManager: tabManager, windowWidth: windowWidth)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { tabManager.addTab() } label: {
                Image(systemName: "plus")
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}

// MARK: - Tab Strip (Safari風のグループ背景)

// ウィンドウ幅を親から伝えるための PreferenceKey。
struct WindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// タブ列の実寸幅を測るための PreferenceKey。
private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// タブ列を1つのガラス容器でまとめ、Safariのようなグルーピング背景を出す。
// iOS 26ではGlassEffectContainerで容器ガラスと各タブのガラスをAppleの仕組みで馴染ませて融合。
//
// 幅の挙動（少数タブ→中身に合わせて縮み中央、 大量タブ→利用可能幅で頭打ち＋横スクロール）は
// 純正だけでは両立できないため、最小限の自前計測で実現する：
//   1. 0サイズの不可視プローブで「中身の実寸幅」を測る（レイアウト幅には影響しない）
//   2. 表示側のピル容器を min(実寸, 利用可能幅) に固定し、中身だけをスクロールさせる
//   3. principal スロットが中身サイズで中央配置する
// principal スロットは GeometryReader に実幅を与えないため、利用可能幅は windowWidth
// （ContentViewで計測）から左右のコントロール分を引いて求める。
private struct TabStrip: View {
    var tabManager: TabManager
    var windowWidth: CGFloat
    @State private var contentWidth: CGFloat = 0

    // 左の信号機＋右の＋/歯車＋余白のおおよその予約幅。
    private let reservedWidth: CGFloat = 220

    var body: some View {
        let cap = windowWidth > reservedWidth ? windowWidth - reservedWidth : .greatestFiniteMagnitude
        let stripWidth = contentWidth > 0 ? min(contentWidth, cap) : nil

        ScrollView(.horizontal, showsIndicators: false) {
            tabRow
        }
        .frame(width: stripWidth)
        .clipShape(Capsule())
        .modifier(TabGroupBackground())
        .background(measuringProbe) // 0サイズ。レイアウト幅に影響せず実寸だけ測る。
        .onPreferenceChange(ContentWidthKey.self) { contentWidth = $0 }
    }

    // 中身の実寸を測る不可視プローブ。fixedSizeで幅制約を受けず、frame(0)でレイアウトには寄与しない。
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
                    isActive: index == tabManager.activeIndex,
                    onSelect: { tabManager.selectTab(at: index) },
                    onClose: { tabManager.closeTab(at: index) }
                )
            }
        }
        .padding(5)

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
    // ＋/歯車の純正ボタン（ガラスのカプセル）と縦幅を揃えるための高さ。
    // 合計高さ = この値 + 上下パディング(5×2)。
    static let height: CGFloat = 33
    // タイトル部の固定幅。これを固定することで全タブの横幅を均一にする。
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

// アクティブタブ: iOS 26はインタラクティブなガラス、それ以前はsystemBackground＋アクセント枠。
private struct TabChipStyle: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isActive {
                // 無彩色で明るくtintし、暗い背景から白っぽく浮き上がらせる。
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
