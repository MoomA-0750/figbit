import SwiftUI

// メニューバーからアクティブタブのwebViewへショートカットを橋渡しする軽量オブジェクト。
// WKWebViewを生成しないため、アプリ階層の@Stateで早期生成しても安全。
// TabManagerはContentViewが所有し続け（シーン確立後に生成）、ここへは弱参照で渡す。
@Observable
final class MenuRouter {
    weak var tabManager: TabManager?

    func send(_ key: String, _ modifiers: [ShortcutItem.KeyModifier] = [], label: String) {
        tabManager?.activeTab?.webView.send(
            shortcut: ShortcutItem(label: label, key: key, modifiers: modifiers, sfSymbol: nil)
        )
    }
}

// iPadOS 26のシステムメニューバーへPC版Figma相当の静的メニューを並べる。
// 物理キーのアクセラレータ(.keyboardShortcut)はあえて付けない。付けるとSwiftUIが
// 物理⌘C/⌘V等を横取りし、WebKitネイティブの信頼されたクリップボード処理を壊すため。
struct FigmaMenuCommands: Commands {
    let router: MenuRouter

    var body: some Commands {
        CommandMenu("ツール") {
            item("選択", "v", symbol: "cursorarrow")
            item("フレーム", "f", symbol: "square.dashed")
            item("矩形", "r", symbol: "rectangle")
            item("楕円", "o", symbol: "circle")
            item("ライン", "l", symbol: "line.diagonal")
            item("矢印", "l", [.shift], symbol: "arrow.up.right")
            item("ペン", "p", symbol: "pencil.tip")
            item("鉛筆", "p", [.shift], symbol: "pencil")
            item("テキスト", "t", symbol: "textformat")
            item("手のひら", "h", symbol: "hand.raised")
            item("コメント", "c", symbol: "bubble.left")
            item("スケール", "k", symbol: "arrow.up.left.and.arrow.down.right")
        }

        // 独立した「編集」メニューを作るとローカライズ後に標準のEditメニューと
        // 名前衝突して二重化するため、標準メニューの該当グループを自前項目で置換する。
        CommandGroup(replacing: .undoRedo) {
            item("取り消す", "z", [.cmd], symbol: "arrow.uturn.backward")
            item("やり直す", "z", [.cmd, .shift], symbol: "arrow.uturn.forward")
        }
        CommandGroup(replacing: .pasteboard) {
            item("切り取り", "x", [.cmd], symbol: "scissors")
            item("コピー", "c", [.cmd], symbol: "doc.on.doc")
            item("貼り付け", "v", [.cmd], symbol: "doc.on.clipboard")
            item("複製", "d", [.cmd], symbol: "plus.square.on.square")
            item("削除", "backspace", symbol: "trash")
            Divider()
            item("すべて選択", "a", [.cmd], symbol: "square.dashed.inset.filled")
            item("選択を解除", "escape", symbol: "xmark.square")
        }

        // 標準のViewメニュー（既定では空＝No Menu Items）にズーム項目を入れる。
        CommandGroup(replacing: .sidebar) {
            item("拡大", "=", [.cmd], symbol: "plus.magnifyingglass")
            item("縮小", "-", [.cmd], symbol: "minus.magnifyingglass")
            item("100%にズーム", "0", [.shift], symbol: "percent")
            item("画面に合わせる", "1", [.shift], symbol: "arrow.up.left.and.down.right.magnifyingglass")
            item("選択範囲にズーム", "2", [.shift], symbol: "viewfinder")
            Divider()
            item("UIの表示/非表示", "\\", [.cmd], symbol: "macwindow")
        }

        CommandMenu("オブジェクト") {
            item("グループ化", "g", [.cmd], symbol: "square.on.square")
            item("グループ解除", "g", [.cmd, .shift], symbol: "rectangle.split.2x1")
            item("フレームに入れる", "g", [.cmd, .option], symbol: "rectangle.dashed")
            item("コンポーネント作成", "k", [.cmd, .option], symbol: "diamond")
            item("フラット化", "e", [.cmd], symbol: "square.stack")
            Divider()
            item("最前面へ", "]", [.cmd, .shift], symbol: "arrow.up.to.line")
            item("前面へ", "]", [.cmd], symbol: "arrow.up")
            item("背面へ", "[", [.cmd], symbol: "arrow.down")
            item("最背面へ", "[", [.cmd, .shift], symbol: "arrow.down.to.line")
            Divider()
            item("左右反転", "h", [.shift], symbol: "arrow.left.arrow.right")
            item("上下反転", "v", [.shift], symbol: "arrow.up.arrow.down")
            item("表示/非表示", "h", [.cmd, .shift], symbol: "eye")
            item("ロック/解除", "l", [.cmd, .shift], symbol: "lock")
        }

        CommandMenu("テキスト") {
            item("太字", "b", [.cmd], symbol: "bold")
            item("斜体", "i", [.cmd], symbol: "italic")
            item("下線", "u", [.cmd], symbol: "underline")
            Divider()
            item("左揃え", "l", [.cmd, .option], symbol: "text.alignleft")
            item("中央揃え", "t", [.cmd, .option], symbol: "text.aligncenter")
            item("右揃え", "r", [.cmd, .option], symbol: "text.alignright")
            item("両端揃え", "j", [.cmd, .option], symbol: "text.justify")
        }
    }

    @ViewBuilder
    private func item(
        _ title: LocalizedStringKey,
        _ key: String,
        _ modifiers: [ShortcutItem.KeyModifier] = [],
        symbol: String? = nil
    ) -> some View {
        Button {
            router.send(key, modifiers, label: key)
        } label: {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
    }
}
