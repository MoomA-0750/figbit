import SwiftUI
import WebKit
import UIKit

struct FigmaCanvasView: UIViewRepresentable {
    var tabManager: TabManager
    // 表示するタブを明示的に指定する。nil のときはアクティブタブを表示する（通常のエディタ）。
    // ホーム画面は専用の homeTab を渡して使う。
    var tab: FigmaTab? = nil
    var onPageLoad: ((URL, String) -> Void)? = nil
    // セットされていると、このWebView内でのファイルURLへの遷移を中断し、代わりにこのコールバックを呼ぶ。
    // ホーム画面でファイルを選んだら新規タブで開く挙動（PC版公式アプリ同様）に使う。
    var onOpenFile: ((URL) -> Void)? = nil
    @Environment(AuthManager.self) private var authManager
    @Environment(ShortcutSyncManager.self) private var shortcutSync

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .white
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let tab = tab ?? tabManager.activeTab else { return }
        let webView = tab.webView

        if webView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            context.coordinator.mainWebView = webView
            context.coordinator.observeTitleChanges(of: webView)
            // タブ切替時、既に表示中のURLでログイン状態を即時反映する
            context.coordinator.authManager.updateLoginState(from: webView.url)
            // ホーム画面なら、ファイルカードのクリックを受け取るネイティブ側ハンドラを登録する。
            if onOpenFile != nil {
                context.coordinator.installHomeBridge(on: webView)
            }
        }

        webView.pencilMode = shortcutSync.pencilMode
        // ページ読み込み完了通知のクロージャを毎回更新する（クロージャが参照するobjectが変わり得るため）
        context.coordinator.onPageLoad = onPageLoad
        context.coordinator.onOpenFile = onOpenFile
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(authManager: authManager)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let authManager: AuthManager
        var onPageLoad: ((URL, String) -> Void)?
        var onOpenFile: ((URL) -> Void)?
        weak var mainWebView: WKWebView?
        weak var popupVC: UIViewController?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        // ホームWebViewのファイル切り出し中フラグ。SPA遷移でURLが複数回変わるため二重起動を防ぐ。
        private var isPoppingHomeFile = false
        // ホーム用のネイティブ橋（メッセージハンドラ）を二重登録しないためのフラグ。
        private var didInstallHomeBridge = false

        init(authManager: AuthManager) {
            self.authManager = authManager
        }

        // ホームWebViewのJS（FigmaTab.homeBridgeScript）から送られるファイルURLを受け取るハンドラを登録する。
        // 受け取ったURLは新規タブで開く（フレッシュなタブは確実に描画されるため白画面にならない）。
        func installHomeBridge(on webView: WKWebView) {
            guard !didInstallHomeBridge else { return }
            didInstallHomeBridge = true
            let ucc = webView.configuration.userContentController
            ucc.removeScriptMessageHandler(forName: "figbitOpenFile")
            ucc.add(self, name: "figbitOpenFile")
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "figbitOpenFile",
                  let str = message.body as? String,
                  let url = URL(string: str),
                  Self.isFigmaFileURL(url) else { return }
            onOpenFile?(url)
        }

        deinit {
            titleObservation?.invalidate()
            urlObservation?.invalidate()
        }

        // Figma は SPA なので pushState ナビゲーションでは didFinish/decidePolicyFor が発火しない。
        // title と url の KVO 監視でSPA遷移を拾う。
        // - title: recordVisit を確実に呼ぶ。
        // - url: ホーム画面のWebViewがファイル（エディタ）URLへ遷移したら、それをタブに切り出す。
        func observeTitleChanges(of webView: WKWebView) {
            titleObservation?.invalidate()
            titleObservation = webView.observe(\.title) { [weak self, weak webView] _, _ in
                guard let webView,
                      let url = webView.url,
                      let title = webView.title, !title.isEmpty else { return }
                self?.onPageLoad?(url, title)
            }
            urlObservation?.invalidate()
            urlObservation = webView.observe(\.url) { [weak self, weak webView] _, _ in
                guard let self, let webView, let url = webView.url else { return }
                // 保険: JS傍受をすり抜けてホームWebView自身がファイルへ遷移した場合の復帰処理。
                if self.onOpenFile != nil, webView === self.mainWebView, Self.isFigmaFileURL(url) {
                    self.recoverHomeNavigatedToFile(url, home: webView)
                }
            }
        }

        // 保険経路: ホームWebViewがJS傍受をすり抜けて自分でファイルを開いてしまった場合。
        // そのファイルを新規タブ（フレッシュなので描画OK）で開き直し、ホームは figma.com/files に戻す。
        private func recoverHomeNavigatedToFile(_ url: URL, home: WKWebView) {
            guard !isPoppingHomeFile else { return }
            isPoppingHomeFile = true
            onOpenFile?(url)
            home.load(URLRequest(url: URL(string: "https://www.figma.com/files")!))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.isPoppingHomeFile = false
            }
        }

        // figma.com のファイル（design/file/board/slides/proto + キー）URLか判定する。
        static func isFigmaFileURL(_ url: URL) -> Bool {
            guard url.host?.hasSuffix("figma.com") == true else { return false }
            let parts = url.pathComponents
            guard parts.count >= 3,
                  ["design", "board", "slides", "file", "proto"].contains(parts[1]),
                  !parts[2].isEmpty else { return false }
            return true
        }

        // メインWebViewのナビゲーション完了時のみログイン状態を更新する
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === mainWebView else { return }
            authManager.updateLoginState(from: webView.url)
            if let url = webView.url, let title = webView.title {
                onPageLoad?(url, title)
            }
            // ログイン直後（userHandleが未取得の場合）にユーザー情報を取得する
            if authManager.isLoggedIn == true && authManager.userHandle == nil {
                fetchUserHandle(from: webView)
            }
        }

        private func fetchUserHandle(from webView: WKWebView) {
            // Figmaの内部APIからユーザー情報を取得する。
            // 複数の応答フォーマットに対応し、取得できなければnilを返す。
            let js = """
            try {
                const r = await fetch('/api/user', {credentials: 'same-origin'});
                if (r.ok) {
                    const d = await r.json();
                    const u = (d.meta && d.meta.user) || d.user
                              || (d.handle != null || d.email != null ? d : null);
                    if (u) {
                        const label = u.handle || u.name || u.email;
                        if (label) return label;
                    }
                }
            } catch(e) {}
            return null;
            """
            webView.callAsyncJavaScript(
                js, arguments: [:], in: nil, in: .page
            ) { [weak self] result in
                guard case .success(let value) = result,
                      let handle = value as? String, !handle.isEmpty else { return }
                DispatchQueue.main.async {
                    self?.authManager.userHandle = handle
                }
            }
        }

        // window.open() によるポップアップ（Google OAuthなど）を小窓として表示する。
        // nil を返して親フレームに読み込むと、OAuth完了後の window.close() で画面が空白になるため
        // 必ず WKWebView を返して window.opener 関係を維持する。
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.customUserAgent = webView.customUserAgent
            popup.navigationDelegate = self
            popup.uiDelegate = self

            let contentVC = PopupWebViewController(webView: popup)
            let navVC = UINavigationController(rootViewController: contentVC)
            navVC.modalPresentationStyle = .formSheet
            navVC.preferredContentSize = CGSize(width: 520, height: 680)

            // UIの操作は次のランループに回してデリゲートコールバックから抜けた後に実行する
            DispatchQueue.main.async { [weak webView, weak self] in
                webView?.window?.rootViewController?.present(navVC, animated: true)
                self?.popupVC = navVC
            }

            return popup
        }

        // popup側が window.close() を呼んだ際にシートを閉じる。
        // この後メインWebViewのJSが popup.closed を検知してfigma.com/filesへ遷移し、
        // didFinish が発火してログイン状態が更新される。
        func webViewDidClose(_ webView: WKWebView) {
            DispatchQueue.main.async { [weak self] in
                self?.popupVC?.dismiss(animated: true)
                self?.popupVC = nil
            }
        }
    }
}

// MARK: - OAuth Popup Host

private class PopupWebViewController: UIViewController {
    private let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Figmaにログイン")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
    }
}
