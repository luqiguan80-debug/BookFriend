import Foundation

/// TXT 章节标题启发式识别：逐行扫描，正则宁可漏判不错判
enum TXTChapters {
    private static let patterns: [NSRegularExpression] = {
        let sources = [
            #"^第[0-9零一二三四五六七八九十百千两]{1,7}[章节回部卷篇].{0,30}$"#,
            #"^(楔子|序言?|尾声|后记|番外.{0,10})$"#,
            #"^(Chapter|CHAPTER|Part|PART)\s+[0-9IVXLC]+.{0,40}$"#,
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// 单行是否像章节标题（PDF 文本扫描也复用）
    static func isChapterTitle(_ trimmedLine: String) -> Bool {
        guard !trimmedLine.isEmpty else { return false }
        let range = NSRange(location: 0, length: (trimmedLine as NSString).length)
        return patterns.contains { $0.firstMatch(in: trimmedLine, range: range) != nil }
    }

    /// 章节前缀 key（「第四章 像海龟一样思考」→「第四章」）：PDF 扫描时按它分组去重
    private static let prefixRegex = try? NSRegularExpression(
        pattern: #"^(第[0-9零一二三四五六七八九十百千两]{1,7}[章节回部卷篇]|楔子|序言?|尾声|后记|番外|(Chapter|CHAPTER|Part|PART)\s+[0-9IVXLC]+)"#)
    static func chapterKey(of trimmedLine: String) -> String? {
        let range = NSRange(location: 0, length: (trimmedLine as NSString).length)
        guard let m = prefixRegex?.firstMatch(in: trimmedLine, range: range) else { return nil }
        return (trimmedLine as NSString).substring(with: m.range)
    }

    /// 返回识别到的章节（level 全 0，target 为行首字符偏移）
    static func detect(in text: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        var offset = 0
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isChapterTitle(trimmed) {
                entries.append(TOCEntry(title: trimmed, level: 0, target: offset))
            }
            offset += (line as NSString).length + 1  // +1 换行符
        }
        return entries
    }
}
