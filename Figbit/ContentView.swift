import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(MenuRouter.self) private var menuRouter
    @Environment(FigmaAPIManager.self) private var figmaAPI
    @Environment(\.scenePhase) private var scenePhase
    @State private var tabManager = TabManager()
    @State private var showSettings = false
    @State private var windowWidth: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // editorContent は常に View ツリーに残す。
                // shouldShowNativeHome が true になった瞬間に editorContent を外すと
                // FigmaCanvasView の Coordinator が解放され webView.navigationDelegate が nil になる。
                // その状態でログイン後リダイレクト（figma.com/files）が来ても didFinish が
                // 呼ばれず、authManager.updateLoginState が更新されなくなる。
                editorContent

                ShortcutPanelView()
                    .environment(tabManager)

                // ネイティブホームは editorContent の上に重ねる真のオーバーレイ。
                // Color(.systemBackground) の不透明背景で下層を完全に隠す。
                if shouldShowNativeHome {
                    NativeHomeView(onOpen: openInActiveTab)
                        .environment(figmaAPI)
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
                TabToolbar(tabManager: tabManager, showSettings: $showSettings, windowWidth: windowWidth)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowNativeHome)
        .onAppear { menuRouter.tabManager = tabManager }
        .task {
            if tabManager.tabs.isEmpty { tabManager.restoreSessionOrDefault() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tabManager.saveSession() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(authManager)
                .environment(shortcutSync)
                .environment(tabManager)
                .environment(figmaAPI)
        }
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

    // MARK: - Native Home Condition

    private var shouldShowNativeHome: Bool {
        if tabManager.tabs.isEmpty { return true }
        guard let tab = tabManager.activeTab else { return true }
        guard let url = tab.currentURL else { return true }
        return isHomePage(url)
    }

    private func isHomePage(_ url: URL) -> Bool {
        guard url.host?.hasSuffix("figma.com") == true else { return false }
        let path = url.path
        return path.isEmpty || path == "/" || path.hasPrefix("/files") || path.hasPrefix("/home")
    }

    // Load a URL in the active tab, or create a new tab if none exist.
    private func openInActiveTab(url: URL) {
        if tabManager.tabs.isEmpty {
            tabManager.addTab(url: url)
        } else {
            tabManager.activeTab?.load(url: url)
        }
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
