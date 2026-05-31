import SwiftUI

@main
struct FigbitApp: App {
    @State private var authManager = AuthManager()
    @State private var shortcutSync = ShortcutSyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(shortcutSync)
        }
    }
}
