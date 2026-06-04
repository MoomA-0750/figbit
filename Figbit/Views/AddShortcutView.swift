import SwiftUI

struct AddShortcutView: View {
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    // 通常キーはテキスト入力、特殊キー（Backspace/F1など）はプルダウンで選ぶ。
    // 片方を使うともう片方をクリアし、effectiveKey が実際のキーになる。
    @State private var typedKey = ""
    @State private var specialKey = ""   // 選択中の特殊キーtoken（""=未選択）
    @State private var selectedModifiers: Set<ShortcutItem.KeyModifier> = []
    @State private var sfSymbol = ""
    @State private var showSymbolPicker = false

    private var effectiveKey: String {
        specialKey.isEmpty ? typedKey.lowercased() : specialKey
    }

    var isValid: Bool { !label.isEmpty && !effectiveKey.isEmpty }

    // ⌘C/⌘V/⌘Xはレイヤーに対しては合成イベントで成立しないため、設定時に警告する。
    private var showsClipboardWarning: Bool {
        selectedModifiers == [.cmd] && ["c", "v", "x"].contains(effectiveKey)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ボタン") {
                    TextField("ラベル（例: コンポーネント）", text: $label)
                    symbolPickerRow
                }

                Section {
                    TextField("キー（例: f, r, z, 1）", text: $typedKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: typedKey) { _, newValue in
                            if !newValue.isEmpty { specialKey = "" }
                        }
                    Picker("特殊キー", selection: $specialKey) {
                        Text("なし").tag("")
                        ForEach(ShortcutItem.specialKeys, id: \.token) { sk in
                            Text(sk.name).tag(sk.token)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: specialKey) { _, newValue in
                        if !newValue.isEmpty { typedKey = "" }
                    }
                } header: {
                    Text("キー")
                } footer: {
                    Text("通常キーは直接入力、Backspaceやファンクションキーなどは「特殊キー」から選んでください。")
                }

                Section("修飾キー") {
                    ForEach(ShortcutItem.KeyModifier.allCases) { mod in
                        Toggle(isOn: Binding(
                            get: { selectedModifiers.contains(mod) },
                            set: { on in
                                if on { selectedModifiers.insert(mod) }
                                else { selectedModifiers.remove(mod) }
                            }
                        )) {
                            Text(mod.displayName + "  " + mod.rawValue)
                        }
                    }
                }

                if showsClipboardWarning {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("レイヤーのコピー/ペーストはパネルから動作しません")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("ブラウザのセキュリティ制約により、ボタンからの⌘C/⌘V/⌘Xではレイヤーをコピー/切り取り/貼り付けできません（テキストの操作は可能です）。レイヤーは物理キーボードの⌘C/⌘V、または長押し（右クリック）→メニューを指でタップしてください。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if isValid {
                    Section("プレビュー") {
                        let item = buildItem()
                        HStack {
                            Text(item.displayLabel).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(item.label).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("ショートカット追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        shortcutSync.addShortcut(buildItem())
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SFSymbolPickerView(selected: $sfSymbol)
            }
        }
    }

    private var symbolPickerRow: some View {
        Button { showSymbolPicker = true } label: {
            HStack(spacing: 12) {
                if sfSymbol.isEmpty {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    Text("アイコンを選択（省略可）")
                        .foregroundStyle(.placeholder)
                } else {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    Text(sfSymbol)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func buildItem() -> ShortcutItem {
        ShortcutItem(
            label: label,
            key: effectiveKey,
            modifiers: ShortcutItem.KeyModifier.allCases.filter { selectedModifiers.contains($0) },
            sfSymbol: sfSymbol.isEmpty ? nil : sfSymbol
        )
    }
}
