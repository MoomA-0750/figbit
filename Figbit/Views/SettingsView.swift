import SwiftUI

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
                tabSection
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
                        Text(LocalizedStringKey(mode.label)).font(.body)
                        Text(LocalizedStringKey(mode.description)).font(.caption).foregroundStyle(.secondary)
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
            Picker("保存先", selection: Binding(
                get: { shortcutSync.storageLocation },
                set: { shortcutSync.storageLocation = $0 }
            )) {
                ForEach(ShortcutStorageLocation.allCases) { loc in
                    Text(loc.label).tag(loc)
                }
            }

            ForEach(shortcutSync.shortcuts) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(item.label))
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
            Text("「この端末に保存」はこのiPad内にのみ保存します。「iCloudに同期」は複数のiPad間で自動同期します（iCloudの有効化が必要です）。")
        }
    }

    private let retentionOptions = [7, 14, 30, 60, 90, 0]

    private var tabSection: some View {
        Section {
            Toggle("前回のタブを復元", isOn: Binding(
                get: { tabManager.restoreTabsEnabled },
                set: { tabManager.restoreTabsEnabled = $0 }
            ))
            if tabManager.restoreTabsEnabled {
                Picker("タブの保持期間", selection: Binding(
                    get: { tabManager.tabRetentionDays },
                    set: { tabManager.tabRetentionDays = $0 }
                )) {
                    ForEach(retentionOptions, id: \.self) { days in
                        if days <= 0 {
                            Text("無期限").tag(days)
                        } else {
                            Text("\(days)日").tag(days)
                        }
                    }
                }
            }
        } header: {
            Text("タブ")
        } footer: {
            Text("アプリ再起動時に、前回開いていたタブを復元します。最後に開いてから設定した期間が過ぎたタブは自動的に閉じます。")
        }
    }

    private var accountSection: some View {
        Section("Figmaアカウント") {
            if authManager.isLoggedIn == true {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ログイン済み")
                            .font(.body)
                        if let handle = authManager.userHandle, !handle.isEmpty {
                            Text(handle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            } else {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        authManager.presentLogin(navigating: tabManager.activeTab)
                    }
                } label: {
                    Label("Figmaにログイン", systemImage: "person.crop.circle")
                }
            }

            Button(role: .destructive) {
                authManager.clearSession(then: tabManager.activeTab)
            } label: {
                Label("セッションをクリア", systemImage: "trash")
            }
        }
    }
}
