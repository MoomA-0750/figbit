import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @State private var tabManager = TabManager()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabBarView(tabManager: tabManager, showSettings: $showSettings)
                    .frame(height: 48)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .overlay(alignment: .bottom) { Divider() }

                FigmaCanvasView(tabManager: tabManager)
                    .ignoresSafeArea(edges: .bottom)
            }

            ShortcutPanelView()
                .environment(tabManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(authManager)
                .environment(shortcutSync)
                .environment(tabManager)
        }
    }
}
