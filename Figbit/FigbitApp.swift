import SwiftUI

@main
struct FigbitApp: App {
    @State private var authManager = AuthManager()
    @State private var shortcutSync = ShortcutSyncManager()
    @State private var menuRouter = MenuRouter()
    @State private var figmaAPI = FigmaAPIManager()

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
