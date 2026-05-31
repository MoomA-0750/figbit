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
        return "\(modStr)\(key.uppercased())"
    }

    var jsKeyCode: String {
        if key.count == 1 {
            let c = key.uppercased()
            if c >= "A", c <= "Z" { return "Key\(c)" }
            if c >= "0", c <= "9" { return "Digit\(c)" }
        }
        switch key.lowercased() {
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
}

extension ShortcutItem {
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
        ShortcutItem(label: "コピー", key: "c", modifiers: [.cmd], sfSymbol: "doc.on.doc"),
        ShortcutItem(label: "貼り付け", key: "v", modifiers: [.cmd], sfSymbol: "clipboard"),
    ]
}
