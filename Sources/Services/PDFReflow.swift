import Foundation
import PDFKit

/// PDF 重排引擎（类 WPS 阅读模式）：抽取文字 → 去页眉页脚 → 碎行合并回段落 →
/// 标题识别（正则 + 内容流真实字号双通道）→ 恢复加粗，输出结构化文本块。
enum PDFReflow {

    struct Block {
        enum Kind { case heading, paragraph }
        let kind: Kind
        let text: String
        var bold: Bool = false
    }

    /// 重排结果：文本块 + 每个 PDF 页在纯文本中的起始字符偏移（阅读模式下目录跳转用）
    struct Result {
        let blocks: [Block]
        let pageOffsets: [Int]
    }

    /// 一行文字 + 内容流对齐来的字体信息（size 为 0 表示未取得）
    private struct Line {
        let text: String
        let size: CGFloat
        let name: String
    }

    static func extract(from url: URL) -> Result {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return Result(blocks: [], pageOffsets: [0]) }

        // 1. 逐页抽行（文字版直接有；扫描版读导入时 OCR 加的文字层）+ 字体信息对齐
        var pageLines: [[Line]] = []
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { pageLines.append([]); continue }
            let rawLines = (page.string ?? "").components(separatedBy: .newlines)
                .map { cleanSpaces($0.trimmingCharacters(in: .whitespaces)) }
            let runs = page.pageRef.flatMap { PDFFontScan.scan(page: $0) } ?? []
            pageLines.append(assignFonts(lines: rawLines, runs: runs))
        }

        // 2. 页眉页脚：跨页高频出现的短行（书名/标题/页脚），及纯页码行
        var freq: [String: Int] = [:]
        for lines in pageLines {
            for line in Set(lines.map(\.text)) where !line.isEmpty && line.count <= 30 {
                freq[line, default: 0] += 1
            }
        }
        let threshold = max(3, doc.pageCount / 4)
        let junk = Set(freq.filter { $0.value >= threshold }.map(\.key))
        func isJunk(_ text: String) -> Bool {
            if text.isEmpty { return true }
            if junk.contains(text) { return true }
            let t = text.replacingOccurrences(of: " ", with: "")
            // 纯页码：12 / -12- / 第12页
            if t.range(of: #"^-?\d{1,4}-?$"#, options: .regularExpression) != nil { return true }
            if t.range(of: #"^第?\d{1,4}页$"#, options: .regularExpression) != nil { return true }
            return false
        }
        let cleaned = pageLines.map { $0.filter { !isJunk($0.text) } }

        // 3. 碎行合并回段落（记录每页在纯文本中的起始偏移；字体感知标题/加粗）
        let fullLen = typicalLineLength(cleaned)
        var blocks: [Block] = []
        var pageOffsets = [0]   // 第 0 页从 0 开始
        var plainLen = 0        // 已产出纯文本长度（块文本 + 块间换行）
        var current = ""
        var boldChars = 0       // 当前段落中粗体字体的字符数
        var plainChars = 0
        func flush() {
            let t = current.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                let bold = plainChars > 0 && boldChars * 5 >= plainChars * 3   // ≥60% 粗体字符
                blocks.append(Block(kind: .paragraph, text: t, bold: bold))
                plainLen += t.count + 1
            }
            current = ""
            boldChars = 0
            plainChars = 0
        }
        for lines in cleaned {
            let body = bodySize(of: lines)
            for line in lines {
                let boldFont = isBoldFont(line.name)
                let sizeSaysHeading = body > 0 && line.size >= body * 1.25
                if TXTChapters.isChapterTitle(line.text) || sizeSaysHeading
                    || (boldFont && body > 0 && line.size >= body * 1.1) {
                    flush()
                    blocks.append(Block(kind: .heading, text: line.text, bold: true))
                    plainLen += line.text.count + 1
                    continue
                }
                if boldFont { boldChars += line.text.count }
                plainChars += line.text.count
                // 全角/半角缩进开头 = 新段落
                if line.text.hasPrefix("　") || line.text.hasPrefix("  ") { flush() }
                let stripped = line.text.replacingOccurrences(of: "^[　 ]+", with: "", options: .regularExpression)
                current = current.isEmpty ? stripped : joinLines(current, stripped)
                // 明显短行（不足满行 55%）= 段落收尾
                if line.text.count < Int(Double(fullLen) * 0.55) { flush() }
            }
            flush()  // 页边界强制收段，防止页眉残留/跨页乱并
            pageOffsets.append(plainLen)   // 下一页从这里开始
        }
        flush()
        return Result(blocks: blocks, pageOffsets: pageOffsets)
    }

    /// 清洗 OCR/抽取产生的多余空格：中文字之间、中文与中文标点之间的空格删掉。
    /// （OCR 文字层按识别块插空格，不清洗会出现「海龟 们」「被称 为」）
    private static func cleanSpaces(_ s: String) -> String {
        guard s.contains(" ") else { return s }
        var result = s
        let han = #"一-鿿"#
        let punct = #"，。、；：？！“”‘’（）《》〈〉【】…—·"#
        let rules = [
            "([\(han)]) ([\(han)])",
            "([\(han)]) ([\(punct)])",
            "([\(punct)]) ([\(han)])",
            "([\(punct)]) ([\(punct)])",
        ]
        for rule in rules {
            guard let re = try? NSRegularExpression(pattern: rule) else { continue }
            while let m = re.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
                let g1 = (result as NSString).substring(with: m.range(at: 1))
                let g2 = (result as NSString).substring(with: m.range(at: 2))
                result = (result as NSString).replacingCharacters(in: m.range, with: g1 + g2)
            }
        }
        return result
    }

    /// 把内容流的字体 run 按字符数顺序对齐到每一行（行尾换行计 1 个虚拟字符）
    private static func assignFonts(lines: [String], runs: [PDFFontScan.Run]) -> [Line] {
        guard !runs.isEmpty else { return lines.map { Line(text: $0, size: 0, name: "") } }
        var result: [Line] = []
        var runIdx = 0, runUsed = 0
        func advance(_ n: Int) {
            var n = n
            while n > 0, runIdx < runs.count {
                let remain = runs[runIdx].chars - runUsed
                if n < remain { runUsed += n; n = 0 }
                else { n -= remain; runIdx += 1; runUsed = 0 }
            }
        }
        for line in lines {
            let mid = line.count / 2
            advance(mid)
            let size = runIdx < runs.count ? runs[runIdx].size : 0
            let name = runIdx < runs.count ? runs[runIdx].name : ""
            advance(line.count - mid + 1)   // +1 抵换行符
            result.append(Line(text: line, size: size, name: name))
        }
        return result
    }

    /// 每页正文字号：按行长加权的众数（取 0.1 精度）
    private static func bodySize(of lines: [Line]) -> CGFloat {
        var weight: [Int: Int] = [:]
        for line in lines where line.size > 0 && !line.text.isEmpty {
            weight[Int((line.size * 10).rounded()), default: 0] += line.text.count
        }
        guard let best = weight.max(by: { $0.value < $1.value }) else { return 0 }
        return CGFloat(best.key) / 10
    }

    private static func isBoldFont(_ name: String) -> Bool {
        let n = name.lowercased()
        // Light/Regular/Medium 优先排除（如 STHeitiSC-Light 含 heiti 但不是粗体）
        if n.contains("light") || n.contains("regular") || n.contains("medium") { return false }
        return n.contains("bold") || n.contains("heavy") || n.contains("black") || n.contains("heiti")
            || name.contains("黑体") || name.contains("粗")
    }

    /// 中英文混排断行合并：两侧都是 ASCII 字母数字则补空格，中文直接连
    private static func joinLines(_ a: String, _ b: String) -> String {
        guard let last = a.last, let first = b.first else { return a + b }
        if last.isASCII, first.isASCII,
           (last.isLetter || last.isNumber), (first.isLetter || first.isNumber) {
            return a + " " + b
        }
        return a + b
    }

    /// 「满行」长度：取所有够长的行的 75 分位，作为短行判定基准
    private static func typicalLineLength(_ pages: [[Line]]) -> Int {
        var lens: [Int] = []
        for lines in pages {
            for line in lines where line.text.count > 10 { lens.append(line.text.count) }
        }
        guard !lens.isEmpty else { return 30 }
        lens.sort()
        return lens[lens.count * 3 / 4]
    }
}
