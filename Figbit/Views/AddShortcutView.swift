import SwiftUI

struct AddShortcutView: View {
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(\.dismiss) private var dismiss

    let editingItem: ShortcutItem?

    @State private var label: String
    // 通常キーはテキスト入力、特殊キー（Backspace/F1など）はプルダウンで選ぶ。
    // 片方を使うともう片方をクリアし、effectiveKey が実際のキーになる。
    @State private var typedKey: String
    @State private var specialKey: String   // 選択中の特殊キーtoken（""=未選択）
    @State private var selectedModifiers: Set<ShortcutItem.KeyModifier>
    @State private var sfSymbol: String
    @State private var showSymbolPicker = false

    init(editingItem: ShortcutItem? = nil) {
        self.editingItem = editingItem
        if let item = editingItem {
            _label = State(initialValue: item.label)
            _sfSymbol = State(initialValue: item.sfSymbol ?? "")
            _selectedModifiers = State(initialValue: Set(item.modifiers))
            let isSpecial = ShortcutItem.specialKeys.map(\.token).contains(item.key)
            _typedKey = State(initialValue: isSpecial ? "" : item.key)
            _specialKey = State(initialValue: isSpecial ? item.key : "")
        } else {
            _label = State(initialValue: "")
            _typedKey = State(initialValue: "")
            _specialKey = State(initialValue: "")
            _selectedModifiers = State(initialValue: [])
            _sfSymbol = State(initialValue: "")
        }
    }

    private var effectiveKey: String {
        specialKey.isEmpty ? typedKey.lowercased() : specialKey
    }

    private var isModifierOnly: Bool { effectiveKey.isEmpty && !selectedModifiers.isEmpty }
    var isValid: Bool { !label.isEmpty && (!effectiveKey.isEmpty || !selectedModifiers.isEmpty) }

    // ⌘C/⌘V/⌘Xはレイヤーに対しては合成イベントで成立しないため、設定時に警告する。
    private var showsClipboardWarning: Bool {
        selectedModifiers == [.cmd] && ["c", "v", "x"].contains(effectiveKey)
    }

    private var isEditing: Bool { editingItem != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    menuCommandPicker
                } footer: {
                    Text("削除やグループ化など、キーボードショートカットがわからない機能もここから選べばラベル・キー・アイコンが自動で埋まります。")
                }

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
                    Text("通常キーは直接入力、Backspaceやファンクションキーなどは「特殊キー」から選んでください。キーを指定しない場合、修飾キーのみのホールドボタン（押している間だけ修飾キーが有効）になります。")
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
            .navigationTitle(isEditing ? "ショートカット編集" : "ショートカット追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "追加") {
                        if isEditing {
                            shortcutSync.updateShortcut(buildItem())
                        } else {
                            shortcutSync.addShortcut(buildItem())
                        }
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

    private var menuCommandPicker: some View {
        Menu {
            ForEach(MenuCommandCatalog.sections, id: \.name) { section in
                Menu(section.name) {
                    ForEach(section.commands) { c in
                        Button { applyMenuCommand(c) } label: {
                            Label(LocalizedStringKey(c.title), systemImage: c.symbol)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "filemenu.and.selection")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                Text("Figmaのメニューから選択")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // メニューコマンドを選んだら、その内容でフォーム各項目を埋める。
    private func applyMenuCommand(_ c: MenuCommand) {
        label = c.title
        selectedModifiers = Set(c.modifiers)
        sfSymbol = c.symbol
        if ShortcutItem.specialKeys.map(\.token).contains(c.key) {
            specialKey = c.key
            typedKey = ""
        } else {
            typedKey = c.key
            specialKey = ""
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
            id: editingItem?.id ?? UUID(),
            label: label,
            key: effectiveKey,
            modifiers: ShortcutItem.KeyModifier.allCases.filter { selectedModifiers.contains($0) },
            sfSymbol: sfSymbol.isEmpty ? nil : sfSymbol,
            kind: isModifierOnly ? .modifierHold : .shortcut
        )
    }
}
