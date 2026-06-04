# Figbit

iPadOS向けFigmaラッパーアプリ。WKWebViewでfigma.comを包み、Apple PencilとカスタムショートカットパネルによってiPadでの快適なFigma操作を実現する個人使用アプリ。

## Language

### アプリ・レイアウト

**TabBar（タブバー）**:
画面最上部に配置されるコントロール領域。ブラウザスタイルのFigmaファイルタブ複数枚と、リロード・戻る・設定等のコントロールボタンを含む。
_Avoid_: ナビゲーションバー、ツールバー

**Canvas（キャンバス）**:
TabBarの下、画面全体を占めるWKWebView領域。figma.comのUI全体がここに表示される。
_Avoid_: WebView領域、Figma画面

**Settings（設定画面）**:
TabBar上の設定ボタンから開く全設定を網羅する画面。ShortcutPanel設定・PencilMode設定・認証管理をすべてここで行う。
_Avoid_: 設定パネル、環境設定

### ショートカット

**ShortcutPanel（ショートカットパネル）**:
Figmaショートカットをボタンとして並べたフローティングパネル。収納時は画面端にタブのみ表示され、引き出すと画面上を自由にドラッグ移動できる（iOS PiP方式）。
_Avoid_: キーボードパネル、ツールパレット

**ShortcutButton（ショートカットボタン）**:
ShortcutPanel内に配置される1つのボタン。タップするとWKWebViewに対応するキーイベントを送信する。ユーザーが追加・削除・並び替え可能。
_Avoid_: ショートカットキー、ツールボタン

**CustomShortcut（カスタムショートカット）**:
ユーザーが任意のキーコンビネーションを指定して作成するShortcutButton。Figmaのデフォルトショートカット以外の操作も登録できる。
_Avoid_: ユーザー定義キー

### Apple Pencil・入力

**PencilMode（ペンシルモード）**:
Apple PencilとタッチをどうWKWebViewに伝えるかの設定。デフォルトはFigurativeMode（Pencil=カーソル、指=パン・ズーム）。Settings画面で変更可能。
_Avoid_: 入力モード、タッチ設定

**FigurativeMode（フィギュラティブモード）**:
PencilModeのデフォルト値。Apple Pencil入力をマウスPointerEventとして注入し、指タッチをパン・ズームジェスチャーとして処理する。
_Avoid_: デフォルトモード

### 認証・データ

**Session（セッション）**:
SFSafariViewControllerで認証後にWKWebViewへ引き継がれるFigmaのログイン状態（クッキー）。
_Avoid_: ログイン状態、トークン

**ShortcutData（ショートカットデータ）**:
ユーザーがカスタマイズしたShortcutButtonの構成（並び順・内容）。iCloud Syncで複数iPad間に同期される。
_Avoid_: 設定データ、ショートカット設定

## Example dialogue

> 「ShortcutPanelを開いたままCanvasをパンしたいんだけど、PencilModeをどう設定すればいい？」
>
> 「FigurativeModeのままなら指でパンできます。PencilModeをSettings画面で変えれば、Apple Pencilがない場合でもタッチ操作でカーソル移動できるモードに切り替えられます。」
>
> 「CustomShortcutでCmd+Shift+Hを登録したら、そのSessionが切れても設定は残る？」
>
> 「はい、ShortcutDataはiCloud Syncで永続化されるのでSessionとは独立して保持されます。」
