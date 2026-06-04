import Foundation
import AuthenticationServices
import UIKit

@Observable
class FigmaAPIManager {

    // OAuth client credentials — set by the user in Settings.
    // client_id is not sensitive; client_secret is stored in Keychain.
    var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Keys.clientID) }
    }
    var clientSecret: String {
        didSet { KeychainHelper.setOptional(clientSecret.isEmpty ? nil : clientSecret,
                                           forKey: Keys.clientSecret) }
    }

    // Tokens stored in Keychain; expiry date stored in UserDefaults.
    private(set) var accessToken: String? {
        didSet { KeychainHelper.setOptional(accessToken, forKey: Keys.accessToken) }
    }
    private var refreshToken: String? {
        didSet { KeychainHelper.setOptional(refreshToken, forKey: Keys.refreshToken) }
    }
    private var tokenExpiry: Date? {
        didSet {
            if let d = tokenExpiry {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Keys.tokenExpiry)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.tokenExpiry)
            }
        }
    }

    var teamIDs: [String] {
        didSet { UserDefaults.standard.set(teamIDs, forKey: Keys.teamIDs) }
    }
    var recentFiles: [RecentFigmaFile] = []
    var cachedUser: FigmaAPIUser?

    var isAuthenticated: Bool { accessToken != nil }
    var hasCredentials: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    private static let redirectURI = "figbit://oauth/callback"

    private enum Keys {
        static let clientID     = "figbit.oauth.clientID.v1"
        static let clientSecret = "figbit.oauth.clientSecret"
        static let accessToken  = "figbit.oauth.accessToken"
        static let refreshToken = "figbit.oauth.refreshToken"
        static let tokenExpiry  = "figbit.oauth.tokenExpiry.v1"
        static let teamIDs      = "figbit.api.teamIDs.v1"
        static let recents      = "figbit.api.recents.v1"
    }

    private let maxRecents = 24
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    // Strong reference kept while ASWebAuthenticationSession is in progress
    private var authSession: ASWebAuthenticationSession?

    init() {
        clientID     = UserDefaults.standard.string(forKey: Keys.clientID)     ?? ""
        clientSecret = KeychainHelper.get(forKey: Keys.clientSecret)           ?? ""
        accessToken  = KeychainHelper.get(forKey: Keys.accessToken)
        refreshToken = KeychainHelper.get(forKey: Keys.refreshToken)
        teamIDs      = UserDefaults.standard.stringArray(forKey: Keys.teamIDs) ?? []
        if let ts = UserDefaults.standard.object(forKey: Keys.tokenExpiry) as? Double {
            tokenExpiry = Date(timeIntervalSince1970: ts)
        }
        loadRecents()
    }

    // MARK: - OAuth Flow

    // Opens figma.com/oauth in an in-app browser and exchanges the code for tokens.
    func signIn() async throws {
        guard !clientID.isEmpty, !clientSecret.isEmpty else { throw OAuthError.missingCredentials }

        let state = UUID().uuidString
        guard var comps = URLComponents(string: "https://www.figma.com/oauth") else {
            throw OAuthError.badURL
        }
        // scope はURLに含めず、Figma Developerポータルで設定したアプリのスコープを使う。
        // URLに含めると、アプリのスコープ設定と不一致のとき 400 "Invalid scopes for app" になる。
        comps.queryItems = [
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "redirect_uri",  value: Self.redirectURI),
            URLQueryItem(name: "state",         value: state),
            URLQueryItem(name: "response_type", value: "code"),
        ]
        guard let authURL = comps.url else { throw OAuthError.badURL }

        // ASWebAuthenticationSession — intercepts figbit:// redirect without URL scheme registration
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "figbit"
            ) { [weak self] url, error in
                self?.authSession = nil
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: OAuthError.noCallback); return }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = PresentationContextProvider.shared
            session.start()
            authSession = session
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw OAuthError.stateMismatch }

        try await exchangeCode(code)
    }

    func signOut() {
        accessToken  = nil
        refreshToken = nil
        tokenExpiry  = nil
        cachedUser   = nil
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

        if isAuthenticated, recentFiles.first(where: { $0.key == key })?.thumbnailUrl == nil {
            enqueueThumbnailFetch(for: key)
        }
    }

    func enrichThumbnailsIfNeeded() {
        guard isAuthenticated else { return }
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

    // MARK: - Private: OAuth token management

    private func exchangeCode(_ code: String) async throws {
        let tokenURL = URL(string: "https://api.figma.com/v1/oauth/token")!
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")
        req.httpBody = [
            "code":         code,
            "grant_type":   "authorization_code",
            "redirect_uri": Self.redirectURI,
        ].formEncoded()

        let token = try await performTokenRequest(req)
        accessToken  = token.accessToken
        refreshToken = token.refreshToken
        tokenExpiry  = token.expiresIn > 0 ? Date().addingTimeInterval(Double(token.expiresIn)) : nil
    }

    // Refreshes the access token when it is within 5 minutes of expiry.
    private func refreshAccessTokenIfNeeded() async throws {
        guard let expiry = tokenExpiry, Date() > expiry.addingTimeInterval(-300),
              let rt = refreshToken else { return }

        let refreshURL = URL(string: "https://api.figma.com/v1/oauth/refresh")!
        var req = URLRequest(url: refreshURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")
        req.httpBody = [
            "refresh_token": rt,
            "grant_type":    "refresh_token",
        ].formEncoded()

        do {
            let token = try await performTokenRequest(req)
            accessToken = token.accessToken
            if let newRefresh = token.refreshToken { refreshToken = newRefresh }
            tokenExpiry = token.expiresIn > 0 ? Date().addingTimeInterval(Double(token.expiresIn)) : nil
        } catch {
            // Refresh failed — clear tokens so the user is prompted to sign in again
            accessToken  = nil
            refreshToken = nil
            tokenExpiry  = nil
            throw OAuthError.refreshFailed
        }
    }

    private func performTokenRequest(_ req: URLRequest) async throws -> OAuthTokenResponse {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed(
                (resp as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private func basicAuthHeader() -> String {
        let raw = "\(clientID):\(clientSecret)"
        let encoded = raw.data(using: .utf8)!.base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Private: REST helper

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await refreshAccessTokenIfNeeded()
        guard let token = accessToken else { throw OAuthError.notAuthenticated }
        guard let url = URL(string: "https://api.figma.com\(path)") else {
            throw OAuthError.badURL
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw OAuthError.badResponse }
        guard http.statusCode == 200 else { throw OAuthError.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Private: Thumbnail fetching

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

    // MARK: - Error types

    enum OAuthError: Error, LocalizedError {
        case missingCredentials
        case badURL
        case noCallback
        case stateMismatch
        case tokenExchangeFailed(Int)
        case refreshFailed
        case notAuthenticated
        case badResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:          "Client IDとClient Secretを設定してください"
            case .badURL:                      "URLの生成に失敗しました"
            case .noCallback:                  "コールバックURLを受信できませんでした"
            case .stateMismatch:               "stateパラメータが一致しません（セキュリティエラー）"
            case .tokenExchangeFailed(let c):  "トークン取得に失敗しました (HTTP \(c))"
            case .refreshFailed:               "トークンの更新に失敗しました。再度ログインしてください"
            case .notAuthenticated:            "未認証です。Figmaでサインインしてください"
            case .badResponse:                 "レスポンスが無効です"
            case .http(let c):                 "APIエラー (HTTP \(c))"
            }
        }
    }
}

// MARK: - Token response model

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
    }
}

// MARK: - ASWebAuthenticationSession presentation context

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow) ?? UIWindow()
    }
}

// MARK: - Helper: Dictionary → URL-encoded form body

private extension Dictionary where Key == String, Value == String {
    func formEncoded() -> Data? {
        map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
    }
}
