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

    // メニュー項目はMenuCommandCatalogが単一の真実の源。こことパネルの追加画面が
    // 同じカタログを参照するため、項目の追加・変更は一箇所で済む。
    var body: some Commands {
        CommandMenu("ツール") {
            ForEach(MenuCommandCatalog.tools) { item($0) }
        }

        // 独立した「編集」メニューを作るとローカライズ後に標準のEditメニューと
        // 名前衝突して二重化するため、標準メニューの該当グループを自前項目で置換する。
        CommandGroup(replacing: .undoRedo) {
            ForEach(MenuCommandCatalog.undoRedo) { item($0) }
        }
        CommandGroup(replacing: .pasteboard) {
            ForEach(MenuCommandCatalog.editPrimary) { item($0) }
            Divider()
            ForEach(MenuCommandCatalog.editSelection) { item($0) }
        }

        // 標準のViewメニュー（既定では空＝No Menu Items）にズーム項目を入れる。
        CommandGroup(replacing: .sidebar) {
            ForEach(MenuCommandCatalog.viewZoom) { item($0) }
            Divider()
            ForEach(MenuCommandCatalog.viewUI) { item($0) }
        }

        CommandMenu("オブジェクト") {
            ForEach(MenuCommandCatalog.objectGroup) { item($0) }
            Divider()
            ForEach(MenuCommandCatalog.objectArrange) { item($0) }
            Divider()
            ForEach(MenuCommandCatalog.objectTransform) { item($0) }
        }

        CommandMenu("テキスト") {
            ForEach(MenuCommandCatalog.textStyle) { item($0) }
            Divider()
            ForEach(MenuCommandCatalog.textAlign) { item($0) }
        }
    }

    @ViewBuilder
    private func item(_ c: MenuCommand) -> some View {
        Button {
            router.send(c.key, c.modifiers, label: c.key)
        } label: {
            Label(LocalizedStringKey(c.title), systemImage: c.symbol)
        }
    }
}
