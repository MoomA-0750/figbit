import Foundation

struct ShortcutItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var key: String
    var modifiers: [KeyModifier]
    var sfSymbol: String?

    enum KeyModifier: String, Codable, CaseIterable, Identifiable {
        case cmd = "cmd"
        case shift = "shift"
        case option = "option"
        case ctrl = "ctrl"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .cmd: return "⌘"
            case .shift: return "⇧"
            case .option: return "⌥"
            case .ctrl: return "⌃"
            }
        }
        var jsKey: String {
            switch self {
            case .cmd: return "metaKey"
            case .shift: return "shiftKey"
            case .option: return "altKey"
            case .ctrl: return "ctrlKey"
            }
        }
    }

    var displayLabel: String {
        let modStr = modifiers.map { $0.displayName }.joined()
        return "\(modStr)\(keyGlyph)"
    }

    // 特殊キーは記号で見やすく表示する（例: backspace → ⌫、f1 → F1）。
    var keyGlyph: String {
        switch key.lowercased() {
        case "backspace": return "⌫"
        case "delete": return "⌦"
        case "enter", "return": return "↩"
        case "tab": return "⇥"
        case "escape": return "⎋"
        case " ", "space": return "␣"
        case "arrowup": return "↑"
        case "arrowdown": return "↓"
        case "arrowleft": return "←"
        case "arrowright": return "→"
        default: return key.uppercased()
        }
    }

    var jsKeyCode: String {
        if key.count == 1 {
            let c = key.uppercased()
            if c >= "A", c <= "Z" { return "Key\(c)" }
            if c >= "0", c <= "9" { return "Digit\(c)" }
        }
        let lower = key.lowercased()
        if lower.hasPrefix("f"), let n = Int(lower.dropFirst()), (1...12).contains(n) {
            return "F\(n)"
        }
        switch lower {
        case " ", "space": return "Space"
        case "escape": return "Escape"
        case "enter": return "Enter"
        case "backspace": return "Backspace"
        case "delete": return "Delete"
        case "tab": return "Tab"
        case "arrowup": return "ArrowUp"
        case "arrowdown": return "ArrowDown"
        case "arrowleft": return "ArrowLeft"
        case "arrowright": return "ArrowRight"
        case "[": return "BracketLeft"
        case "]": return "BracketRight"
        case ",": return "Comma"
        case ".": return "Period"
        case "/": return "Slash"
        default: return key
        }
    }

    // legacy keyCode/which 値。Figmaのキャンバスはこの旧APIでショートカットを判定するため必須。
    var keyCodeValue: Int {
        if key.count == 1, let scalar = key.uppercased().unicodeScalars.first {
            let v = Int(scalar.value)
            if v >= 65, v <= 90 { return v }   // A-Z
            if v >= 48, v <= 57 { return v }   // 0-9
        }
        let lower = key.lowercased()
        if lower.hasPrefix("f"), let n = Int(lower.dropFirst()), (1...12).contains(n) {
            return 111 + n   // F1=112 ... F12=123
        }
        switch lower {
        case " ", "space": return 32
        case "escape": return 27
        case "enter", "return": return 13
        case "backspace": return 8
        case "delete": return 46
        case "tab": return 9
        case "arrowup": return 38
        case "arrowdown": return 40
        case "arrowleft": return 37
        case "arrowright": return 39
        case "[": return 219
        case "]": return 221
        case ",": return 188
        case ".": return 190
        case "/": return 191
        case "-": return 189
        case "=": return 187
        case ";": return 186
        case "'": return 222
        case "\\": return 220
        case "`": return 192
        default:
            if let scalar = key.uppercased().unicodeScalars.first { return Int(scalar.value) }
            return 0
        }
    }
}

extension ShortcutItem {
    // 設定画面のプルダウン用。token は jsKeyCode/keyCodeValue が解釈できる値に揃える。
    static let specialKeys: [(token: String, name: String)] = [
        ("backspace", "Backspace ⌫"),
        ("delete", "Delete ⌦"),
        ("enter", "Enter ↩"),
        ("tab", "Tab ⇥"),
        ("escape", "Escape ⎋"),
        ("space", "Space ␣"),
        ("arrowup", "↑ 上矢印"),
        ("arrowdown", "↓ 下矢印"),
        ("arrowleft", "← 左矢印"),
        ("arrowright", "→ 右矢印"),
        ("f1", "F1"), ("f2", "F2"), ("f3", "F3"), ("f4", "F4"),
        ("f5", "F5"), ("f6", "F6"), ("f7", "F7"), ("f8", "F8"),
        ("f9", "F9"), ("f10", "F10"), ("f11", "F11"), ("f12", "F12"),
    ]

    static let defaults: [ShortcutItem] = [
        ShortcutItem(label: "選択", key: "v", modifiers: [], sfSymbol: "cursorarrow"),
        ShortcutItem(label: "フレーム", key: "f", modifiers: [], sfSymbol: "rectangle.dashed"),
        ShortcutItem(label: "矩形", key: "r", modifiers: [], sfSymbol: "rectangle"),
        ShortcutItem(label: "テキスト", key: "t", modifiers: [], sfSymbol: "textformat"),
        ShortcutItem(label: "手のひら", key: "h", modifiers: [], sfSymbol: "hand.raised"),
        ShortcutItem(label: "拡大鏡", key: "z", modifiers: [], sfSymbol: "magnifyingglass"),
        ShortcutItem(label: "フィット", key: "1", modifiers: [.shift], sfSymbol: "arrow.up.left.and.down.right.magnifyingglass"),
        ShortcutItem(label: "コンポーネント", key: "k", modifiers: [.cmd], sfSymbol: "square.on.square"),
        ShortcutItem(label: "元に戻す", key: "z", modifiers: [.cmd], sfSymbol: "arrow.uturn.backward"),
        ShortcutItem(label: "やり直す", key: "z", modifiers: [.cmd, .shift], sfSymbol: "arrow.uturn.forward"),
        // レイヤーのコピー/ペーストは合成イベントでは成立しないため、初期プリセットから除外。
        // （テキストは可能。レイヤーは物理キーボードか長押し右クリック→指タップが必要）
    ]
}
