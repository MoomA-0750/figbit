import SwiftUI
import WebKit
import UIKit

struct FigmaCanvasView: UIViewRepresentable {
    var tabManager: TabManager
    @Environment(AuthManager.self) private var authManager
    @Environment(ShortcutSyncManager.self) private var shortcutSync

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .white
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let tab = tabManager.activeTab else { return }
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
            // タブ切替時、既に表示中のURLでログイン状態を即時反映する
            context.coordinator.authManager.updateLoginState(from: webView.url)
        }

        webView.pencilMode = shortcutSync.pencilMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(authManager: authManager)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let authManager: AuthManager
        weak var mainWebView: WKWebView?
        weak var popupVC: UIViewController?

        init(authManager: AuthManager) {
            self.authManager = authManager
        }

        // メインWebViewのナビゲーション完了時のみログイン状態を更新する
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === mainWebView else { return }
            authManager.updateLoginState(from: webView.url)
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
