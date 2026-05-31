import Foundation
import WebKit

@Observable
class TabManager {
    var tabs: [FigmaTab] = []
    var activeIndex: Int = 0

    private let processPool = WKProcessPool()
    private let dataStore = WKWebsiteDataStore.default()

    var activeTab: FigmaTab? {
        guard tabs.indices.contains(activeIndex) else { return nil }
        return tabs[activeIndex]
    }

    init() {
        addTab()
    }

    func addTab(url: URL = URL(string: "https://www.figma.com")!) {
        let tab = FigmaTab(processPool: processPool, dataStore: dataStore)
        tabs.append(tab)
        activeIndex = tabs.count - 1
        tab.load(url: url)
    }

    func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        activeIndex = max(0, min(activeIndex, tabs.count - 1))
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
    }

    func goBack() { activeTab?.webView.goBack() }
    func goForward() { activeTab?.webView.goForward() }
    func reload() {
        guard let wv = activeTab?.webView else { return }
        if wv.isLoading { wv.stopLoading() } else { wv.reload() }
    }
}
