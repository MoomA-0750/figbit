import SwiftUI

@main
struct FigbitApp: App {
    @State private var authManager = AuthManager()
    @State private var shortcutSync = ShortcutSyncManager()
    @State private var menuRouter = MenuRouter()
    @State private var figmaAPI = FigmaAPIManager()

    init() {
        // 端末フォントをFigmaへ供給する橋を初期化する（CoreTextでフォントを事前列挙）。
        FontHelper.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(shortcutSync)
                .environment(menuRouter)
                .environment(figmaAPI)
        }
        .commands {
            FigmaMenuCommands(router: menuRouter)
        }
    }
}
