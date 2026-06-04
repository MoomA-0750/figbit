import Foundation

@Observable
class FigmaAPIManager {

    // Personal Access Token — Figma > Settings > Account > Personal access tokens
    var personalAccessToken: String {
        didSet {
            UserDefaults.standard.set(personalAccessToken, forKey: Keys.pat)
            cachedUser = nil
        }
    }

    // Team IDs entered by the user for the project browser.
    // Each ID is the numeric string visible in figma.com/files/team/{id}/…
    var teamIDs: [String] {
        didSet { UserDefaults.standard.set(teamIDs, forKey: Keys.teamIDs) }
    }

    // Locally-tracked files the user has opened in the app
    var recentFiles: [RecentFigmaFile] = []

    var cachedUser: FigmaAPIUser?
    var hasToken: Bool { !personalAccessToken.trimmingCharacters(in: .whitespaces).isEmpty }

    private enum Keys {
        static let pat     = "figbit.api.pat.v1"
        static let teamIDs = "figbit.api.teamIDs.v1"
        static let recents = "figbit.api.recents.v1"
    }

    private let maxRecents = 24
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]

    init() {
        personalAccessToken = UserDefaults.standard.string(forKey: Keys.pat) ?? ""
        teamIDs = UserDefaults.standard.stringArray(forKey: Keys.teamIDs) ?? []
        loadRecents()
    }

    // MARK: - Recent file tracking

    // Called whenever a tab finishes loading a Figma file URL.
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

        if hasToken, recentFiles.first(where: { $0.key == key })?.thumbnailUrl == nil {
            enqueueThumbnailFetch(for: key)
        }
    }

    // Kick off thumbnail fetches for all recents that are missing them.
    func enrichThumbnailsIfNeeded() {
        guard hasToken else { return }
        for file in recentFiles where file.thumbnailUrl == nil {
            enqueueThumbnailFetch(for: file.key)
        }
    }

    // MARK: - REST API

    func fetchMe() async throws -> FigmaAPIUser {
        if let cached = cachedUser { return cached }
        let user = try await get("/v1/me", as: FigmaAPIUser.self)
        cachedUser = user
        return user
    }

    func fetchProjects(teamID: String) async throws -> [FigmaAPIProject] {
        let r = try await get("/v1/teams/\(teamID)/projects", as: FigmaProjectsResponse.self)
        return r.projects
    }

    func fetchFiles(projectID: String) async throws -> [FigmaAPIFile] {
        let r = try await get("/v1/projects/\(projectID)/files", as: FigmaProjectFilesResponse.self)
        return r.files
    }

    func fetchFileMeta(key: String) async throws -> FigmaFileMetaResponse {
        try await get("/v1/files/\(key)?depth=1", as: FigmaFileMetaResponse.self)
    }

    // MARK: - Private

    private func enqueueThumbnailFetch(for key: String) {
        guard thumbnailTasks[key] == nil else { return }
        thumbnailTasks[key] = Task {
            do {
                let meta = try await fetchFileMeta(key: key)
                if let idx = recentFiles.firstIndex(where: { $0.key == key }) {
                    recentFiles[idx].thumbnailUrl = meta.thumbnailUrl
                    recentFiles[idx].name = meta.name
                    saveRecents()
                }
            } catch {}
            thumbnailTasks[key] = nil
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        guard hasToken else { throw APIError.noToken }
        guard let url = URL(string: "https://api.figma.com\(path)") else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        req.setValue(
            personalAccessToken.trimmingCharacters(in: .whitespaces),
            forHTTPHeaderField: "X-Figma-Token"
        )
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func extractKey(from url: URL) -> String? {
        guard url.host?.hasSuffix("figma.com") == true else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3 else { return nil }
        guard ["design", "board", "slides", "file", "proto"].contains(parts[1]) else { return nil }
        return parts[2]
    }

    private func extractKind(from url: URL) -> RecentFigmaFile.Kind? {
        guard url.host?.hasSuffix("figma.com") == true else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "design", "file", "proto": return .design
        case "board": return .figjam
        case "slides": return .slides
        default: return nil
        }
    }

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

    enum APIError: Error, LocalizedError {
        case noToken, badURL, badResponse, http(Int)
        var errorDescription: String? {
            switch self {
            case .noToken:         "Personal Access Tokenが設定されていません"
            case .badURL:          "URLが無効です"
            case .badResponse:     "レスポンスが無効です"
            case .http(let code):  "APIエラー (HTTP \(code))"
            }
        }
    }
}
