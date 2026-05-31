import Foundation

enum PencilMode: String, CaseIterable, Identifiable, Codable {
    case figurative = "figurative"
    case touchCursor = "touchCursor"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .figurative: return "FigurativeMode"
        case .touchCursor: return "TouchCursorMode"
        }
    }

    var description: String {
        switch self {
        case .figurative: return "Apple Pencil → カーソル操作 / 指 → パン・ズーム"
        case .touchCursor: return "指 → カーソル操作（Apple Pencilなし環境向け）"
        }
    }
}
