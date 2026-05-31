import Foundation
import WebKit
import Combine

@Observable
class FigmaTab: Identifiable {
    let id = UUID()
    var title: String = "Figma"
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var currentURL: URL?

    let webView: PencilAwareWebView
    private var cancellables: Set<AnyCancellable> = []

    init(processPool: WKProcessPool, dataStore: WKWebsiteDataStore) {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = PencilAwareWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = false
        self.webView = webView

        webView.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in self?.title = t?.isEmpty == false ? t! : "Figma" }
            .store(in: &cancellables)

        webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.isLoading = v }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.canGoBack = v }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.canGoForward = v }
            .store(in: &cancellables)

        webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.currentURL = v }
            .store(in: &cancellables)
    }

    func load(url: URL = URL(string: "https://www.figma.com")!) {
        webView.load(URLRequest(url: url))
    }
}
