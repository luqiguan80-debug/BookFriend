import Foundation
import SwiftData

// 选中状态（JS → Swift，EPUB 用）
struct SelectionState {
    var text: String
    var context: String
    var offset: Int
    var rectY: CGFloat
}

struct SelectionPayload {
    var text: String
    var context: String
    var offset: Int
    var bookID: UUID
    var bookTitle: String
    var author: String
    var chapterIndex: Int
    var chapterTitle: String
}

/// AI 面板的输入
struct AIRequest: Identifiable {
    let id = UUID()
    var action: NoteType
    var payload: SelectionPayload
}

/// TXT/PDF 选段上下文提取：取选区前后各 radius 个字符（EPUB 走 ReaderJS 块级元素，不用这里）
enum SelectionContext {
    static let radius = 500

    /// range 为 text 的 UTF-16 NSRange（UITextView.selectedRange / PDFSelection.range(at:on:) 都是）
    static func around(_ range: NSRange, in text: String, radius: Int = radius) -> String {
        let ns = text as NSString
        let loc = max(range.location - radius, 0)
        let end = min(NSMaxRange(range) + radius, ns.length)
        guard end > loc else { return "" }
        return ns.substring(with: NSRange(location: loc, length: end - loc))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 全局簿记层（不再负责 UI 事件路由；各阅读器自行管理选段动作条）
@MainActor
final class SelectionCenter: ObservableObject {
    static let shared = SelectionCenter()
    var modelContext: ModelContext?
}
