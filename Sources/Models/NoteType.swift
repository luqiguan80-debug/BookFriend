import Foundation

enum NoteType: String, Codable, CaseIterable {
    case highlight, explain, translate, expand

    var displayName: String {
        switch self {
        case .highlight: return "批注"
        case .explain: return "讲解"
        case .translate: return "翻译"
        case .expand: return "展开"
        }
    }
}
