import Foundation
import WebKit
import SafariServices
import UIKit

@Observable
class AuthManager {
    var isShowingSafari = false

    private var pendingWebView: WKWebView?
    private let safariDelegate = SafariDelegate()

    init() {
        safariDelegate.owner = self
    }

    func handleGoogleAuthURL(_ url: URL, for webView: WKWebView, from viewController: UIViewController) {
        pendingWebView = webView
        let safari = SFSafariViewController(url: url)
        safari.delegate = safariDelegate
        safari.preferredControlTintColor = .systemBlue
        viewController.present(safari, animated: true)
    }

    func transferCookies(to webView: WKWebView) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        for cookie in allCookies where cookie.domain.hasSuffix("figma.com") {
            cookieStore.setCookie(cookie)
        }
    }

    fileprivate func didFinishSafari() {
        guard let webView = pendingWebView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.transferCookies(to: webView)
            webView.reload()
        }
        pendingWebView = nil
    }
}

private class SafariDelegate: NSObject, SFSafariViewControllerDelegate {
    weak var owner: AuthManager?

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        DispatchQueue.main.async {
            self.owner?.didFinishSafari()
        }
    }
}
