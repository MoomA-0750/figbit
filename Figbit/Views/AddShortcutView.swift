import SwiftUI

struct AddShortcutView: View {
    @Environment(ShortcutSyncManager.self) private var shortcutSync
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var key = ""
    @State private var selectedModifiers: Set<ShortcutItem.KeyModifier> = []
    @State private var sfSymbol = ""

    var isValid: Bool { !label.isEmpty && !key.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("ボタン") {
                    TextField("ラベル（例: コンポーネント）", text: $label)
                    TextField("SF Symbol名（省略可）", text: $sfSymbol)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("キー") {
                    TextField("キー（例: f, r, z, 1）", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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
        }
    }

    private func buildItem() -> ShortcutItem {
        ShortcutItem(
            label: label,
            key: key.lowercased(),
            modifiers: ShortcutItem.KeyModifier.allCases.filter { selectedModifiers.contains($0) },
            sfSymbol: sfSymbol.isEmpty ? nil : sfSymbol
        )
    }
}
