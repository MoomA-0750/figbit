import Foundation
import WebKit

@Observable
class TabManager {
    var tabs: [FigmaTab] = []
    var activeIndex: Int = 0

    // アプリ再起動時に前回のタブを復元するか。UserDefaultsに永続化する。
    var restoreTabsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(restoreTabsEnabled, forKey: Keys.restoreEnabled)
            if !restoreTabsEnabled { clearSavedSession() }
        }
    }

    // タブの保持日数。最後に開いてからこの日数を過ぎたタブは復元時に閉じる。0以下は無期限。
    var tabRetentionDays: Int {
        didSet { UserDefaults.standard.set(tabRetentionDays, forKey: Keys.retentionDays) }
    }

    private let processPool = WKProcessPool()
    private let dataStore = WKWebsiteDataStore.default()

    private enum Keys {
        static let restoreEnabled = "figbit.restoreTabs.enabled.v1"
        static let sessionURLs = "figbit.session.urls.v1"
        static let sessionActiveIndex = "figbit.session.activeIndex.v1"
        static let sessionTimestamps = "figbit.session.timestamps.v1"
        static let retentionDays = "figbit.restoreTabs.retentionDays.v1"
    }

    init() {
        restoreTabsEnabled = UserDefaults.standard.object(forKey: Keys.restoreEnabled) as? Bool ?? true
        tabRetentionDays = UserDefaults.standard.object(forKey: Keys.retentionDays) as? Int ?? 30
    }

    var activeTab: FigmaTab? {
        guard tabs.indices.contains(activeIndex) else { return nil }
        return tabs[activeIndex]
    }

    // url を省略するとページを読み込まず、ネイティブホーム画面が表示される。
    func addTab(url: URL? = nil) {
        let tab = FigmaTab(processPool: processPool, dataStore: dataStore)
        tabs.append(tab)
        activeIndex = tabs.count - 1
        if let url { tab.load(url: url) }
    }

    func closeTab(at index: Int) {
        tabs.remove(at: index)
        // tabs が空になってもネイティブホームが表示されるので guard は不要。
        activeIndex = max(0, min(activeIndex, max(tabs.count - 1, 0)))
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        tabs[index].lastAccessedAt = Date()
    }

    func goBack() { activeTab?.webView.goBack() }
    func goForward() { activeTab?.webView.goForward() }
    func reload() {
        guard let wv = activeTab?.webView else { return }
        if wv.isLoading { wv.stopLoading() } else { wv.reload() }
    }

    // MARK: - Session Restore

    // 起動時に呼ぶ。復元がOFFか保存が無ければ既定の1タブを開く。
    // 最後に開いてから保持期間を過ぎたタブは復元せず（＝自動で閉じる）。
    func restoreSessionOrDefault() {
        guard restoreTabsEnabled,
              let urls = UserDefaults.standard.stringArray(forKey: Keys.sessionURLs),
              !urls.isEmpty else {
            addTab()
            return
        }
        let timestamps = UserDefaults.standard.array(forKey: Keys.sessionTimestamps) as? [Double] ?? []
        let savedActive = UserDefaults.standard.integer(forKey: Keys.sessionActiveIndex)
        let cutoff: Date? = tabRetentionDays > 0
            ? Calendar.current.date(byAdding: .day, value: -tabRetentionDays, to: Date())
            : nil

        var newActiveIndex = 0
        for (i, str) in urls.enumerated() {
            guard let url = URL(string: str) else { continue }
            let ts = i < timestamps.count ? Date(timeIntervalSince1970: timestamps[i]) : Date()
            if let cutoff, ts < cutoff { continue }
            let tab = FigmaTab(processPool: processPool, dataStore: dataStore)
            tab.lastAccessedAt = ts
            if i == savedActive { newActiveIndex = tabs.count }
            tabs.append(tab)
            tab.load(url: url)
        }
        // タブがなければネイティブホームを表示するためここでは何も作らない。
        guard !tabs.isEmpty else { return }
        activeIndex = min(max(newActiveIndex, 0), tabs.count - 1)
    }

    // バックグラウンド遷移時などに呼ぶ。最新のURLと最終アクセス時刻を保存する。
    func saveSession() {
        guard restoreTabsEnabled else { return }
        // 表示中のタブは「今開いている」ので最終アクセス時刻を更新する。
        activeTab?.lastAccessedAt = Date()
        var urls: [String] = []
        var timestamps: [Double] = []
        var newActive = 0
        for (i, tab) in tabs.enumerated() {
            if let s = (tab.webView.url ?? tab.currentURL)?.absoluteString {
                if i == activeIndex { newActive = urls.count }
                urls.append(s)
                timestamps.append(tab.lastAccessedAt.timeIntervalSince1970)
            }
        }
        guard !urls.isEmpty else { return }
        UserDefaults.standard.set(urls, forKey: Keys.sessionURLs)
        UserDefaults.standard.set(timestamps, forKey: Keys.sessionTimestamps)
        UserDefaults.standard.set(newActive, forKey: Keys.sessionActiveIndex)
    }

    func clearSavedSession() {
        UserDefaults.standard.removeObject(forKey: Keys.sessionURLs)
        UserDefaults.standard.removeObject(forKey: Keys.sessionTimestamps)
        UserDefaults.standard.removeObject(forKey: Keys.sessionActiveIndex)
    }
}
