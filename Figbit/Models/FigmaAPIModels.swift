import Foundation

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
