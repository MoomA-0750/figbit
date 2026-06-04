import Foundation
import WebKit
import Combine

@Observable
class FigmaTab: Identifiable {
    let id = UUID()
    var title: String = "Figma"
    // 最後にこのタブを開いた（選択した）時刻。保持期間の判定に使う。
    var lastAccessedAt: Date = Date()
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
            .sink { [weak self] t in self?.title = FigmaTab.cleanTitle(t) }
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

    func load(url: URL = URL(string: "https://www.figma.com/files")!) {
        webView.load(URLRequest(url: url))
    }

    // ブラウザのページタイトル末尾に付く「 – Figma」等のサフィックスを取り除く。
    // 「Figma Slides」を「Figma」より先に判定して " Slides" の取り残しを防ぐ。
    static func cleanTitle(_ raw: String?) -> String {
        guard var t = raw, !t.isEmpty else { return "Figma" }
        let suffixes = [
            " – Figma Slides", " - Figma Slides",
            " – FigJam", " - FigJam",
            " – Figma", " - Figma",
        ]
        for s in suffixes where t.hasSuffix(s) {
            t = String(t.dropLast(s.count))
            break
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Figma" : t
    }

    // 開いているページの種類。URLパスから判定し、タブのアイコンに使う。
    enum Kind {
        case design, figjam, slides, other
        var symbol: String {
            switch self {
            case .design: return "paintbrush.pointed"
            case .figjam: return "hand.draw"
            case .slides: return "play.rectangle"
            case .other:  return "doc"
            }
        }
    }

    var kind: Kind {
        guard let path = currentURL?.path else { return .other }
        if path.hasPrefix("/design/") || path.hasPrefix("/file/") { return .design }
        if path.hasPrefix("/board/") { return .figjam }
        if path.hasPrefix("/slides/") { return .slides }
        return .other
    }
}
