import Foundation
import WebKit

@Observable
class AuthManager {
    // nil = まだfigma.comにアクセスしていない
    var isLoggedIn: Bool? = nil
    // ログイン済みのアカウント表示名（handle / 名前 / メール）
    var userHandle: String? = nil

    func updateLoginState(from url: URL?) {
        guard let url, url.host?.hasSuffix("figma.com") == true else { return }
        let path = url.path
        let isAuthPage = path == "/login" || path.hasPrefix("/login/")
            || path == "/signup" || path.hasPrefix("/signup/")
        isLoggedIn = !isAuthPage
        if isLoggedIn == false {
            userHandle = nil
        }
    }

    func presentLogin(navigating tab: FigmaTab?) {
        guard let tab else { return }
        tab.webView.load(URLRequest(url: URL(string: "https://www.figma.com/login")!))
    }

    func clearSession(then tab: FigmaTab? = nil) {
        isLoggedIn = nil
        userHandle = nil
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            DispatchQueue.main.async { tab?.load() }
        }
    }
}
