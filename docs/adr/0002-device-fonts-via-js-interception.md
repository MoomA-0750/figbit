# ADR 0002: 端末フォントをJS傍受＋sfnt再構築でFigmaへ供給する

**Status**: Accepted（一部ブロック中。下記「制約」参照）

## Context

目標は、Figbit内のWKWebViewで開いたFigmaキャンバスに端末インストール済みフォントを出すこと（最優先課題）。先行事例は廃止済みiPadアプリ「figurative」。

Figmaのデスクトップ版は「フォントヘルパー」というローカルサービスに問い合わせて端末フォントを列挙・描画する。これをアプリ内で再現する必要がある。実機診断で以下を確定した。

- 最新のFigma Webは `https://figmadaemon.com:44960` に問い合わせる（旧来の `127.0.0.1:44950`/`:18412` ではない）。`figmadaemon.com` は127.0.0.1へ解決する公開ドメインで、正規CA署名のTLS証明書を持つ。秘密鍵はFigmaしか持たないため、ローカルサーバでの成りすましは不可能。
- WebKitは `https://figma.com` → `http://127.0.0.1`（ループバック平文）を混在コンテンツとして遮断する。Chromeのlocalhost例外はWKWebViewに無い。よってローカルHTTPサーバ方式は不成立。
- Figmaは `navigator.maxTouchPoints === 0` のときだけフォントヘルパーを探す。iPad（touch=5）では機能ごと無効化される。
- サンドボックスではシステムフォント実体（`/System/Library/Fonts`）のバイト読み取りに制限がある。

## Decision

ネットワークに出る前にページ内で `fetch` / `XMLHttpRequest` を documentStart で乗っ取り、`figmadaemon.com` 宛の `/figma/version`・`/figma/font-files`・`/figma/font-file` をネイティブ（CoreText）のデータで応答する。

- `navigator.maxTouchPoints` を 0 に偽装してFigmaにフォント探索を行わせる（タッチ操作は阻害されないことを実機確認済み）。
- ネイティブ側は `WKScriptMessageHandlerWithReply`（`FontHelper`）で応答。フォント実体は `CTFontCopyAvailableTables` / `CTFontCopyTable` で取得したテーブルから sfnt（TTF/OTF）コンテナをその場で再構築して供給する。これによりファイル読み取り権限が不要になり、サンドボックスの壁を回避する。
- フォント一覧のキーには PostScript 名を用いる（ファイルURL不要）。

## Reasons

- ローカルサーバ方式はTLS成りすまし不可＋混在コンテンツ遮断で原理的に不成立。JS傍受はネットワーク層を経由しないため両問題を同時に回避できる。
- sfnt再構築により「実体ファイルが読めない」問題を解消でき、URLに依存しない列挙も可能になる。

## 制約（重要）— ユーザーインストール済みフォントは有料アカウント必須

第三者アプリの `CTFontCollectionCreateFromAvailableFonts` は Apple同梱のシステムフォント（約86ファミリ）しか返さない。構成プロファイルや「設定 > 一般 > フォント」でユーザーが入れたフォント（例: LINESeedJP_OTF, Cera Pro, Chillax, Moralerspace Radon JPDOC）は含まれない。

これらを列挙するにはエンタイトルメント `com.apple.developer.user-fonts`（値 `app-usage` ＝ "Fonts" capability）が必要。エンタイトルメントファイルは `Figbit/Figbit.entitlements` にコミット済みだが、ビルド設定（`CODE_SIGN_ENTITLEMENTS`）からは外してある。

理由: 現在の開発チームは**無料（個人）Apple開発者チーム**であり、Xcodeが明示的に拒否する（"Personal development teams … do not support the Fonts capability."）。有効化には**有料のApple Developer Program（年99ドル）**加入が必須。

## Consequences

- 現状: システムフォント（約86ファミリ）はFigmaのフォントピッカーに出て利用できる。Figmaが使うのは `fetch` ではなく `XHR`（実機ログで確認）。
- ユーザーのカスタムフォントは、コードではなく無料アカウント制限のみが原因でブロックされている。コードは準備完了。
- 有料アカウント移行後の再開手順:
  1. Xcode → ターゲット → Signing & Capabilities → "+ Capability" で **Fonts**（Use Installed Fonts）を追加。
  2. `Figbit.xcodeproj/project.pbxproj` の Debug/Release 両構成に `CODE_SIGN_ENTITLEMENTS = Figbit/Figbit.entitlements;` を戻す。
  3. プロビジョニングプロファイルを再生成してビルド。コードはそのまま動作する想定。
- 無料アカウントのままなら、`UIAppFonts`（アプリ同梱フォント）はエンタイトルメント不要で配信可能だが、「ユーザーが入れた任意のフォント」ではなく「アプリが同梱した固定フォント」に限られる。

## 関連ファイル

- `Figbit/Managers/FontHelper.swift` — 応答ハンドラ＋CoreText列挙＋sfnt再構築。
- `Figbit/Models/FigmaTab.swift` — `fontBridgeScript`（maxTouchPoints偽装＋fetch/XHR傍受）と `figbitFontHelper` ハンドラ登録。
- `Figbit/Views/FigmaCanvasView.swift` — `figbitFontProbe`（ランタイム確認ログ）。
- `Figbit/Figbit.entitlements` — 有料アカウント移行時に有効化するエンタイトルメント。
