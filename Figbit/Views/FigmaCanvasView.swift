import SwiftUI
import WebKit
import SafariServices

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
        }

        webView.pencilMode = shortcutSync.pencilMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(authManager: authManager)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let authManager: AuthManager

        init(authManager: AuthManager) {
            self.authManager = authManager
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            let host = url.host ?? ""
            let isGoogleAuth = host.contains("accounts.google.com") || host.contains("google.com/o/oauth2")
            if isGoogleAuth, navigationAction.targetFrame?.isMainFrame == true {
                DispatchQueue.main.async {
                    if let vc = webView.window?.rootViewController {
                        self.authManager.handleGoogleAuthURL(url, for: webView, from: vc)
                    }
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
