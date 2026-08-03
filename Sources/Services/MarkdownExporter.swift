import Foundation

/// 整书笔记导出为 Markdown（PRD 4.4：可导入 Obsidian/Notion）
enum MarkdownExporter {

    static func markdown(bookTitle: String, author: String, cards: [NoteCard]) -> String {
        var md = "# 《\(bookTitle)》读书笔记\n\n"
        if !author.isEmpty { md += "作者：\(author)\n\n" }
        md += "> 由「书友」自动整理 · \(cards.count) 条笔记\n\n---\n\n"

        let sorted = cards.sorted {
            ($0.chapterIndex, $0.createdAt) < ($1.chapterIndex, $1.createdAt)
        }
        var currentChapter = ""
        for card in sorted {
            let chapter = card.chapterTitle.isEmpty ? "第 \(card.chapterIndex + 1) 节" : card.chapterTitle
            if chapter != currentChapter {
                currentChapter = chapter
                md += "\n## \(chapter)\n\n"
            }
            switch card.type {
            case .highlight:
                md += "> \(card.sourceText.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
                if !card.resultText.isEmpty { md += "批注：\(card.resultText)\n\n" }
            case .explain, .translate, .expand:
                md += "**原文**\n\n> \(card.sourceText.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
                md += "**\(card.type.displayName)**\n\n\(card.resultText)\n\n"
            }
        }
        return md
    }

    static func exportToTempFile(bookTitle: String, author: String, cards: [NoteCard]) throws -> URL {
        let md = markdown(bookTitle: bookTitle, author: author, cards: cards)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(bookTitle)-读书笔记.md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
