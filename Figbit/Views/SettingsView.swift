import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(AuthManager.self) private var authManager
    @Environment(TabManager.self) private var tabManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddShortcut = false
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                pencilModeSection
                shortcutSection
                accountSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showAddShortcut) {
                AddShortcutView()
                    .environment(shortcutSync)
            }
            .confirmationDialog(
                "デフォルトに戻しますか？",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("リセット", role: .destructive) { shortcutSync.resetToDefaults() }
            } message: {
                Text("カスタマイズしたショートカットはすべて削除されます。")
            }
        }
    }

    // MARK: - Sections

    private var pencilModeSection: some View {
        Section {
            ForEach(PencilMode.allCases) { mode in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.label).font(.body)
                        Text(mode.description).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if shortcutSync.pencilMode == mode {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    shortcutSync.pencilMode = mode
                    shortcutSync.save()
                    tabManager.activeTab?.webView.pencilMode = mode
                }
            }
        } header: {
            Text("PencilMode")
        } footer: {
            Text("Apple Pencilと指タッチのキャンバス操作への割り当てを設定します。")
        }
    }

    private var shortcutSection: some View {
        Section {
            ForEach(shortcutSync.shortcuts) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                        Text(item.displayLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                    }
                    Spacer()
                    if let symbol = item.sfSymbol {
                        Image(systemName: symbol).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { shortcutSync.removeShortcuts(at: $0) }
            .onMove { shortcutSync.moveShortcut(from: $0, to: $1) }

            Button(action: { showAddShortcut = true }) {
                Label("ショートカットを追加", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("ShortcutPanel")
                Spacer()
                Button("リセット") { showResetConfirm = true }.font(.caption)
            }
        } footer: {
            Text("ShortcutDataはiCloud経由で複数のiPad間に自動同期されます。")
        }
    }

    private var accountSection: some View {
        Section("Figmaアカウント") {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let webView = tabManager.activeTab?.webView,
                       let vc = webView.window?.rootViewController {
                        authManager.handleGoogleAuthURL(
                            URL(string: "https://www.figma.com/login")!,
                            for: webView,
                            from: vc
                        )
                    }
                }
            } label: {
                Label("Figmaにログイン", systemImage: "safari")
            }

            Button(role: .destructive) {
                WKWebsiteDataStore.default().removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    modifiedSince: .distantPast
                ) { }
            } label: {
                Label("セッションをクリア", systemImage: "trash")
            }
        }
    }
}
