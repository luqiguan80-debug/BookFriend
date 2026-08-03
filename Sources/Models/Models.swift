import Foundation
import SwiftData

enum BookFormat: String, Codable {
    case epub, pdf, txt

    init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "txt": self = .txt
        default: return nil
        }
    }
}

@Model
final class Book {
    // CloudKit 兼容：不可用 .unique，属性需可选或有默认值（UUID 随机生成，天然唯一）
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var formatRaw: String = ""
    /// 原始文件在 Documents/Library 下的文件名
    var fileName: String = ""
    /// 封面图在 Documents/Covers 下的文件名（可选）
    var coverName: String?
    /// 阅读进度：EPUB 用章节序号，PDF 用页码
    var progressLocation: Int = 0
    /// 滚动位置（EPUB 用 Y 偏移，PDF/TXT 用页码/行号）
    var scrollOffset: Double = 0
    var progressFraction: Double = 0
    var lastReadAt: Date = Date.now
    var addedAt: Date = Date.now

    init(id: UUID = UUID(), title: String, author: String = "",
         format: BookFormat, fileName: String, coverName: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.formatRaw = format.rawValue
        self.fileName = fileName
        self.coverName = coverName
        self.progressLocation = 0
        self.scrollOffset = 0
        self.progressFraction = 0
        self.lastReadAt = .now
        self.addedAt = .now
    }

    var format: BookFormat { BookFormat(rawValue: formatRaw) ?? .txt }

    var fileURL: URL { Storage.bookFileURL(fileName: fileName) }

    func deleteFiles() {
        let fm = FileManager.default
        try? fm.removeItem(at: fileURL)
        try? fm.removeItem(at: Storage.extractedDir(for: id))
        if let coverName { try? fm.removeItem(at: Storage.coverURL(coverName: coverName)) }
    }
}

extension Book: Hashable {
    static func == (lhs: Book, rhs: Book) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension NoteCard: Hashable {
    static func == (lhs: NoteCard, rhs: NoteCard) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 笔记卡片：划线和 AI 问答统一沉淀为卡片，按书/章节归档（PRD 4.4）
@Model
final class NoteCard {
    // CloudKit 兼容：不可用 .unique，属性需可选或有默认值
    var id: UUID = UUID()
    var bookID: UUID = UUID()
    var bookTitle: String = ""
    var chapterIndex: Int = 0
    var chapterTitle: String = ""
    var typeRaw: String = ""
    var sourceText: String = ""      // 选中的原文
    var contextText: String = ""     // 所在段落上下文
    var resultText: String = ""      // AI 输出 / 用户批注
    var color: String = "yellow"     // 划线颜色
    /// 选段在章节纯文本中的起始偏移（用于 EPUB 重划线定位）
    var offsetInChapter: Int = 0
    var createdAt: Date = Date.now

    init(bookID: UUID, bookTitle: String, chapterIndex: Int = 0,
         chapterTitle: String = "", type: NoteType,
         sourceText: String, contextText: String = "",
         resultText: String = "", color: String = "yellow",
         offsetInChapter: Int = 0) {
        self.id = UUID()
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.typeRaw = type.rawValue
        self.sourceText = sourceText
        self.contextText = contextText
        self.resultText = resultText
        self.color = color
        self.offsetInChapter = offsetInChapter
        self.createdAt = .now
    }

    var type: NoteType { NoteType(rawValue: typeRaw) ?? .highlight }
}
