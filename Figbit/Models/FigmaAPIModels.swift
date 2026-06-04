import Foundation

// MARK: - API response types (Decodable only, used inside FigmaAPIManager)

struct FigmaAPIUser: Decodable {
    let id: String
    let email: String
    let handle: String
    let imgUrl: String?
    enum CodingKeys: String, CodingKey {
        case id, email, handle
        case imgUrl = "img_url"
    }
}

struct FigmaAPIProject: Decodable, Identifiable {
    let id: String
    let name: String
}

struct FigmaAPIFile: Decodable, Identifiable {
    let key: String
    let name: String
    let thumbnailUrl: String?
    let lastModified: String?
    var id: String { key }
    enum CodingKeys: String, CodingKey {
        case key, name
        case thumbnailUrl = "thumbnail_url"
        case lastModified = "last_modified"
    }
}

struct FigmaProjectsResponse: Decodable {
    let projects: [FigmaAPIProject]
}

struct FigmaProjectFilesResponse: Decodable {
    let files: [FigmaAPIFile]
}

struct FigmaFileMetaResponse: Decodable {
    let name: String
    let thumbnailUrl: String?
    enum CodingKeys: String, CodingKey {
        case name
        case thumbnailUrl = "thumbnail_url"
    }
}

// MARK: - Local recent file record

struct RecentFigmaFile: Codable, Identifiable, Equatable {
    var key: String
    var name: String
    var thumbnailUrl: String?
    var lastOpenedAt: Date
    var kind: Kind

    var id: String { key }

    var openURL: URL {
        switch kind {
        case .design: URL(string: "https://www.figma.com/design/\(key)")!
        case .figjam:  URL(string: "https://www.figma.com/board/\(key)")!
        case .slides:  URL(string: "https://www.figma.com/slides/\(key)")!
        case .other:   URL(string: "https://www.figma.com/file/\(key)")!
        }
    }

    enum Kind: String, Codable {
        case design, figjam, slides, other
        var symbol: String {
            switch self {
            case .design: "paintbrush.pointed"
            case .figjam: "hand.draw"
            case .slides: "play.rectangle"
            case .other:  "doc"
            }
        }
    }
}
