import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(MenuRouter.self) private var menuRouter
    @Environment(FigmaAPIManager.self) private var figmaAPI
    @Environment(\.scenePhase) private var scenePhase
    @State private var tabManager = TabManager()
    @State private var showSettings = false
    @State private var showingHome = true   // ホームボタンで明示的に制御
    @State private var windowWidth: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // editorContent は常に View ツリーに置く（Coordinator 生存のため）。
                // ↑ 詳細は git log を参照。
                editorContent

                ShortcutPanelView()
                    .environment(tabManager)

                if shouldShowHome {
                    // ネイティブUIではなく figma.com/files をそのままホームとして表示する。
                    // ファイルを選ぶと onOpenFile が発火し、新規タブで開く（ホーム自体はタブにしない）。
                    FigmaCanvasView(
                        tabManager: tabManager,
                        tab: tabManager.homeTab,
                        onPageLoad: { url, title in figmaAPI.recordVisit(url: url, title: title) },
                        onOpenFile: openFromHome
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.opacity)
                    .zIndex(1)
                }
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
                TabToolbar(
                    tabManager: tabManager,
                    showSettings: $showSettings,
                    showingHome: $showingHome,
                    windowWidth: windowWidth
                )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowHome)
        .onAppear { menuRouter.tabManager = tabManager }
        .task {
            if tabManager.tabs.isEmpty { tabManager.restoreSessionOrDefault() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tabManager.saveSession() }
        }
        // タブが全部閉じられたらホームに戻す
        .onChange(of: tabManager.tabs.count) { _, count in
            if count == 0 { showingHome = true }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(authManager)
                .environment(shortcutSync)
                .environment(tabManager)
                .environment(figmaAPI)
        }
    }

    // MARK: - Home Condition

    // showingHome を唯一の真実の源にする。
    // タブが 0 枚のときは問答無用でホームを表示する。
    var shouldShowHome: Bool {
        showingHome || tabManager.tabs.isEmpty
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        VStack(spacing: 0) {
            if authManager.isLoggedIn == false {
                loginBanner
            }
            FigmaCanvasView(tabManager: tabManager) { url, title in
                figmaAPI.recordVisit(url: url, title: title)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // ホーム画面からファイルを開く。常に新しいタブを作り、ホームを閉じる。
    func openFromHome(url: URL) {
        tabManager.addTab(url: url)
        showingHome = false
    }

    // MARK: - Login Banner

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
                if tabManager.tabs.isEmpty { tabManager.addTab() }
                authManager.presentLogin(navigating: tabManager.activeTab)
                showingHome = false
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
