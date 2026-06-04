import SwiftUI

@main
struct FigbitApp: App {
    @State private var authManager = AuthManager()
    @State private var shortcutSync = ShortcutSyncManager()
    @State private var menuRouter = MenuRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(shortcutSync)
                .environment(menuRouter)
        }
        .commands {
            FigmaMenuCommands(router: menuRouter)
        }
    }
}
