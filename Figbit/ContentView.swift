import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(MenuRouter.self) private var menuRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var tabManager = TabManager()
    @State private var showSettings = false
    // ツールバーのprincipalスロットはGeometryReaderに実幅を与えないため、
    // ウィンドウ幅をここ（実際に全幅を持つ階層）で測ってタブストリップへ渡す。
    @State private var windowWidth: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    if authManager.isLoggedIn == false {
                        loginBanner
                    }

                    FigmaCanvasView(tabManager: tabManager)
                        .ignoresSafeArea(edges: .bottom)
                }

                ShortcutPanelView()
                    .environment(tabManager)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: WindowWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(WindowWidthKey.self) { windowWidth = $0 }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TabToolbar(tabManager: tabManager, showSettings: $showSettings, windowWidth: windowWidth)
            }
        }
        .onAppear { menuRouter.tabManager = tabManager }
        // 初回フレーム描画後にタブ（WKWebView生成＋figma.com読込）を作る。
        // @State初期化時にやると初回描画までブロックし、起動時に黒い画面が長く残るため。
        // 復元設定がONかつ前回セッションがあれば復元、なければ既定の1タブ。
        .task {
            if tabManager.tabs.isEmpty { tabManager.restoreSessionOrDefault() }
        }
        // アクティブを離れる（バックグラウンド／終了）タイミングで最新URLを保存する。
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tabManager.saveSession() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(authManager)
                .environment(shortcutSync)
                .environment(tabManager)
        }
    }

    private var loginBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.orange)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("ログインが必要です")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Figmaアカウントにログインしてください")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("ログイン") {
                authManager.presentLogin(navigating: tabManager.activeTab)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}
