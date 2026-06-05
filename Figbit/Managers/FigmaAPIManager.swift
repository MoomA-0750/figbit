import Foundation

@Observable
class FigmaAPIManager {

    // アプリ内で実際に開いたファイルの履歴（開いた時刻順）。
    // いずれ実装するiOSホーム画面ウィジェット（最近開いたファイルの一覧）の元データとして保持する。
    var recentFiles: [RecentFigmaFile] = []

    private enum Keys {
        static let recents = "figbit.api.recents.v1"
    }

    private let maxRecents = 24

    init() {
        loadRecents()
    }

    // MARK: - Recent File Tracking

    func recordVisit(url: URL, title: String) {
        guard let key = extractKey(from: url),
              let kind = extractKind(from: url) else { return }
        let cleanedName = FigmaTab.cleanTitle(title)
        let now = Date()

        if let idx = recentFiles.firstIndex(where: { $0.key == key }) {
            recentFiles[idx].lastOpenedAt = now
            if cleanedName != "Figma" { recentFiles[idx].name = cleanedName }
        } else {
            let file = RecentFigmaFile(
                key: key,
                name: cleanedName == "Figma" ? key : cleanedName,
                thumbnailUrl: nil,
                lastOpenedAt: now,
                kind: kind
            )
            recentFiles.insert(file, at: 0)
            if recentFiles.count > maxRecents {
                recentFiles = Array(recentFiles.prefix(maxRecents))
            }
        }

        recentFiles.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        saveRecents()
    }

    // MARK: - Private: URL parsing

    private func extractKey(from url: URL) -> String? {
        guard url.host?.hasSuffix("figma.com") == true else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3,
              ["design", "board", "slides", "file", "proto"].contains(parts[1]) else { return nil }
        return parts[2]
    }

    private func extractKind(from url: URL) -> RecentFigmaFile.Kind? {
        guard url.host?.hasSuffix("figma.com") == true else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "design", "file", "proto": return .design
        case "board":  return .figjam
        case "slides": return .slides
        default: return nil
        }
    }

    // MARK: - Private: Persistence

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Keys.recents),
              let files = try? JSONDecoder().decode([RecentFigmaFile].self, from: data) else { return }
        recentFiles = files
    }

    func saveRecents() {
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: Keys.recents)
        }
    }
}
