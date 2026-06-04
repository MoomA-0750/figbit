# Figbit

iPadOS 向けの Figma ラッパーアプリ。`WKWebView` で figma.com を包み、Apple Pencil とカスタムショートカットパネルによって iPad での快適な Figma 操作を実現する個人使用アプリです。

サービス終了した Figurative（iPad 用 Figma ラッパー）の代替として自作しています。

## 主な機能

- **ブラウザスタイルのタブ** — 複数の Figma ファイルを同時に開き、ファイル種別（Design / FigJam / Slides）に応じたアイコンを表示。前回開いていたタブの復元と、保持期間を過ぎた古いタブの自動クローズに対応。
- **ShortcutPanel** — Figma のキーボードショートカットをボタン化したフローティングパネル。画面端に収納でき、引き出すと自由にドラッグ移動できる（iOS PiP 方式）。ボタンは追加・削除・並び替え・カスタムキー登録が可能。
- **Apple Pencil 対応（PencilMode）** — JavaScript 注入で Apple Pencil を PointerEvent として扱い、ノード選択・移動・描画を可能にする。Pencil と指タッチの割り当ては設定で切り替え可能。
- **iPadOS メニューバー** — ツール・編集・表示・オブジェクト・テキストの各メニューを純正メニューバーに統合。
- **iCloud 同期** — ショートカット等のカスタマイズ設定を `NSUbiquitousKeyValueStore` 経由で複数 iPad 間に自動同期。
- **多言語対応** — String Catalog による日本語 / 英語対応。

## 技術スタック

- **言語 / UI**: Swift 5 / SwiftUI（`@Observable`）
- **最小ターゲット**: iPadOS 17.0（iPad 専用）
- **Web レンダリング**: `WKWebView`
- **認証**: Figma ログイン後のクッキーを `WKWebView` の HTTPCookieStore へ引き継ぎ
- **配布**: 個人使用（TestFlight / Personal Team build）

## プロジェクト構成

```
Figbit/
├── FigbitApp.swift              アプリエントリ／メニューバー定義
├── ContentView.swift            ルートレイアウト（TabBar + Canvas + ShortcutPanel）
├── Models/
│   ├── FigmaTab.swift           1タブの状態（タイトル・URL・種別・最終アクセス時刻）
│   ├── ShortcutItem.swift       ショートカット定義とキーコードマッピング
│   └── PencilMode.swift         Apple Pencil / 指タッチの入力モード
├── Managers/
│   ├── TabManager.swift         タブ管理・セッション復元・保持期間
│   ├── ShortcutSyncManager.swift  ショートカットの iCloud 同期
│   └── AuthManager.swift        Figma 認証・セッション管理
├── Views/
│   ├── TabBarView.swift         タブバー UI
│   ├── FigmaCanvasView.swift    WKWebView ラッパー
│   ├── PencilAwareWebView.swift Apple Pencil / ショートカット注入
│   ├── ShortcutPanelView.swift  フローティングショートカットパネル
│   ├── SettingsView.swift       設定画面
│   ├── AddShortcutView.swift    ショートカット追加画面
│   ├── SFSymbolPickerView.swift SF Symbols 選択
│   ├── FigmaMenuCommands.swift  iPadOS メニューバー項目
│   └── PressEffectButtonStyle.swift  押下エフェクト
└── Localizable.xcstrings        String Catalog（en / ja）
```

設計上の決定事項や用語定義は [`CONTEXT.md`](CONTEXT.md) と [`HANDOFF.md`](HANDOFF.md) を参照してください。

## ビルド

1. Xcode で `Figbit.xcodeproj` を開く
2. iPad（実機推奨）または iPad シミュレータをターゲットに選択
3. 署名チームを自分の Apple ID（Personal Team）に設定
4. Run（⌘R）

> Apple Pencil の挙動は実機でのみ完全に確認できます。
