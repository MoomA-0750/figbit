import Foundation

// Figmaメニューの1項目。ラベル/キー/修飾キー/アイコンを持つ（実質 ShortcutItem 相当）。
// FigmaMenuCommands（メニューバー）と AddShortcutView（パネルへの追加ピッカー）の
// 共通データソース。ここを編集すれば両方に反映される。
struct MenuCommand: Identifiable {
    let title: String
    let key: String
    let modifiers: [ShortcutItem.KeyModifier]
    let symbol: String
    var id: String { "\(title)|\(key)|\(modifiers.map { $0.rawValue }.joined())" }

    // パネルに置くためのショートカットへ変換する。
    func asShortcutItem() -> ShortcutItem {
        ShortcutItem(label: title, key: key, modifiers: modifiers, sfSymbol: symbol)
    }
}

// 各配列は FigmaMenuCommands のメニュー構成（区切り線で分かれる単位）に対応する。
enum MenuCommandCatalog {
    static let tools: [MenuCommand] = [
        .init(title: "選択", key: "v", modifiers: [], symbol: "cursorarrow"),
        .init(title: "フレーム", key: "f", modifiers: [], symbol: "square.dashed"),
        .init(title: "矩形", key: "r", modifiers: [], symbol: "rectangle"),
        .init(title: "楕円", key: "o", modifiers: [], symbol: "circle"),
        .init(title: "ライン", key: "l", modifiers: [], symbol: "line.diagonal"),
        .init(title: "矢印", key: "l", modifiers: [.shift], symbol: "arrow.up.right"),
        .init(title: "ペン", key: "p", modifiers: [], symbol: "pencil.tip"),
        .init(title: "鉛筆", key: "p", modifiers: [.shift], symbol: "pencil"),
        .init(title: "テキスト", key: "t", modifiers: [], symbol: "textformat"),
        .init(title: "手のひら", key: "h", modifiers: [], symbol: "hand.raised"),
        .init(title: "コメント", key: "c", modifiers: [], symbol: "bubble.left"),
        .init(title: "スケール", key: "k", modifiers: [], symbol: "arrow.up.left.and.arrow.down.right"),
    ]

    static let undoRedo: [MenuCommand] = [
        .init(title: "取り消す", key: "z", modifiers: [.cmd], symbol: "arrow.uturn.backward"),
        .init(title: "やり直す", key: "z", modifiers: [.cmd, .shift], symbol: "arrow.uturn.forward"),
    ]

    static let editPrimary: [MenuCommand] = [
        .init(title: "切り取り", key: "x", modifiers: [.cmd], symbol: "scissors"),
        .init(title: "コピー", key: "c", modifiers: [.cmd], symbol: "doc.on.doc"),
        .init(title: "貼り付け", key: "v", modifiers: [.cmd], symbol: "doc.on.clipboard"),
        .init(title: "複製", key: "d", modifiers: [.cmd], symbol: "plus.square.on.square"),
        .init(title: "削除", key: "backspace", modifiers: [], symbol: "trash"),
    ]

    static let editSelection: [MenuCommand] = [
        .init(title: "すべて選択", key: "a", modifiers: [.cmd], symbol: "square.dashed.inset.filled"),
        .init(title: "選択を解除", key: "escape", modifiers: [], symbol: "xmark.square"),
    ]

    static let viewZoom: [MenuCommand] = [
        .init(title: "拡大", key: "=", modifiers: [.cmd], symbol: "plus.magnifyingglass"),
        .init(title: "縮小", key: "-", modifiers: [.cmd], symbol: "minus.magnifyingglass"),
        .init(title: "100%にズーム", key: "0", modifiers: [.shift], symbol: "percent"),
        .init(title: "画面に合わせる", key: "1", modifiers: [.shift], symbol: "arrow.up.left.and.down.right.magnifyingglass"),
        .init(title: "選択範囲にズーム", key: "2", modifiers: [.shift], symbol: "viewfinder"),
    ]

    static let viewUI: [MenuCommand] = [
        .init(title: "UIの表示/非表示", key: "\\", modifiers: [.cmd], symbol: "macwindow"),
    ]

    static let objectGroup: [MenuCommand] = [
        .init(title: "グループ化", key: "g", modifiers: [.cmd], symbol: "square.on.square"),
        .init(title: "グループ解除", key: "g", modifiers: [.cmd, .shift], symbol: "rectangle.split.2x1"),
        .init(title: "フレームに入れる", key: "g", modifiers: [.cmd, .option], symbol: "rectangle.dashed"),
        .init(title: "コンポーネント作成", key: "k", modifiers: [.cmd, .option], symbol: "diamond"),
        .init(title: "フラット化", key: "e", modifiers: [.cmd], symbol: "square.stack"),
    ]

    static let objectArrange: [MenuCommand] = [
        .init(title: "最前面へ", key: "]", modifiers: [.cmd, .shift], symbol: "arrow.up.to.line"),
        .init(title: "前面へ", key: "]", modifiers: [.cmd], symbol: "arrow.up"),
        .init(title: "背面へ", key: "[", modifiers: [.cmd], symbol: "arrow.down"),
        .init(title: "最背面へ", key: "[", modifiers: [.cmd, .shift], symbol: "arrow.down.to.line"),
    ]

    static let objectTransform: [MenuCommand] = [
        .init(title: "左右反転", key: "h", modifiers: [.shift], symbol: "arrow.left.arrow.right"),
        .init(title: "上下反転", key: "v", modifiers: [.shift], symbol: "arrow.up.arrow.down"),
        .init(title: "表示/非表示", key: "h", modifiers: [.cmd, .shift], symbol: "eye"),
        .init(title: "ロック/解除", key: "l", modifiers: [.cmd, .shift], symbol: "lock"),
    ]

    static let textStyle: [MenuCommand] = [
        .init(title: "太字", key: "b", modifiers: [.cmd], symbol: "bold"),
        .init(title: "斜体", key: "i", modifiers: [.cmd], symbol: "italic"),
        .init(title: "下線", key: "u", modifiers: [.cmd], symbol: "underline"),
    ]

    static let textAlign: [MenuCommand] = [
        .init(title: "左揃え", key: "l", modifiers: [.cmd, .option], symbol: "text.alignleft"),
        .init(title: "中央揃え", key: "t", modifiers: [.cmd, .option], symbol: "text.aligncenter"),
        .init(title: "右揃え", key: "r", modifiers: [.cmd, .option], symbol: "text.alignright"),
        .init(title: "両端揃え", key: "j", modifiers: [.cmd, .option], symbol: "text.justify"),
    ]

    // 追加画面のピッカー用：セクション名ごとにまとめる。
    static let sections: [(name: String, commands: [MenuCommand])] = [
        ("ツール", tools),
        ("編集", undoRedo + editPrimary + editSelection),
        ("表示", viewZoom + viewUI),
        ("オブジェクト", objectGroup + objectArrange + objectTransform),
        ("テキスト", textStyle + textAlign),
    ]
}
