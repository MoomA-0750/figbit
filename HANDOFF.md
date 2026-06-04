# Figbit — 引き継ぎドキュメント

## このファイルの目的

新しい開発環境（macOS + Xcode）でClaudeと作業を再開する際に読み込む引き継ぎ資料。
設計上の決定事項はすべてここと `CONTEXT.md` に記録されている。

---

## プロジェクト概要

**Figbit** — iPadOS向けFigmaラッパーアプリ（個人使用、TestFlight配布）

Figurative（iPad用Figmaラッパー）がサービス終了したため、同等機能を自作する。
WKWebViewでfigma.comを包み、Apple PencilとカスタムショートカットパネルでiPadでの快適なFigma操作を実現する。

---

## 確定済みアーキテクチャ

### 技術スタック
- **言語**: Swift / SwiftUI
- **ターゲット**: iPadOS（最小バージョンは未定、要決定）
- **配布**: 個人使用（TestFlight / Personal Team build）

### Figmaアクセス
- WKWebView で `https://www.figma.com` をラップ
- JavaScript注入でApple PencilをPointerEventとして扱う

### 認証
- SFSafariViewControllerでFigmaログイン（Google SSO含め対応）
- 認証後クッキーをWKWebViewのHTTPCookieStoreへ引き継ぐ

### データ永続化
- カスタマイズ設定（ShortcutData等）はiCloud Sync（NSUbiquitousKeyValueStore または CloudKit）
- 複数iPad間で自動同期

---

## 画面レイアウト

```
┌─────────────────────────────────────────┐
│  TabBar: [ファイルタブ...] [←][→][↺][⚙] │  ← 上部固定
├─────────────────────────────────────────┤
│                                         │
│           Canvas (WKWebView)            │  ← 残り全領域
│                                         │
│                        [SP]◀ ショートカットパネル（タブ収納中）
└─────────────────────────────────────────┘
```

### TabBar
- ブラウザスタイルのFigmaファイルタブ（複数同時開放可）
- コントロール: 戻る・進む・リロード
- 設定ボタン（⚙）: Settings画面を開く

### ShortcutPanel（ショートカットパネル）
- **iOS PiP方式**: 収納時は画面端にタブのみ表示、引き出すと画面上を自由にドラッグ移動可能
- カスタマイズはSettings画面で（追加・削除・並び替え・カスタムキーコンビ登録）
- タップでWKWebViewにKeyboardEventを送信（JavaScriptで注入）

### Settings画面
- TabBarの設定ボタンから開く
- 全設定を網羅: ShortcutPanel管理・PencilMode設定・Figmaアカウント管理

---

## Apple Pencil（PencilMode）

| モード | Pencil | 指タッチ |
|--------|--------|----------|
| FigurativeMode（デフォルト） | マウスPointerEventとして注入（カーソル/描画操作） | パン・ズームジェスチャー |
| 設定で変更可 | カスタマイズ可 | カスタマイズ可 |

- Apple Pencilなし環境でも操作に困らないよう、Settings画面でモード変更可能

---

## 解決優先度

1. **Primary（必須）**
   - A: Apple PencilでFigmaのノード選択・移動・描画
   - B: ショートカットパネルによるキーボードショートカット操作

2. **Secondary（追って対応）**
   - C: ピンチズーム・パンの精度改善
   - D: テキスト入力時のシステムキーボードによるキャンバス遮蔽解消

---

## 用語集

`CONTEXT.md`（同ディレクトリ）に完全な用語定義あり。
主要用語: TabBar / Canvas / ShortcutPanel / ShortcutButton / CustomShortcut / PencilMode / FigurativeMode / Session / ShortcutData

---

## 実装の出発点

1. Xcodeで新規iPadOS appプロジェクトを作成（SwiftUI、Bundle ID任意）
2. `WKWebView`でfigma.comをロードする最小構成から開始
3. SFSafariViewController認証フロー実装
4. Apple Pencil → PointerEvent注入のJavaScript実装
5. ShortcutPanel UIの実装
6. Settings画面の実装

---

## 未決定事項（実装時に決める）

- 最小ターゲットiPadOSバージョン（16.0 or 17.0推奨）
- ShortcutPanelのデフォルトショートカット初期セット
- App Bundle ID
