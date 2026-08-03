import SwiftUI
import PDFKit

/// 目录条目：PDF 用页码、TXT 用字符偏移、EPUB 用章节序号做 target
struct TOCEntry: Identifiable {
    let id = UUID()
    var title: String
    var level: Int          // 缩进层级（PDF outline 可能多级）
    var target: Int         // PDF: 页码；TXT: 行首字符偏移；EPUB: 章节序号
    var detail: String? = nil  // 行尾小字（如 PDF 页码）
}

/// 通用目录侧边栏：三种格式、双平台共用，内联在阅读器内容左侧。
/// 视觉与 AIPanelView 一致：小字标题 + 细分隔线 + 主题底色渗出边缘
struct TOCSidebar: View {
    let entries: [TOCEntry]
    var emptyText: String = "这本书没有内置目录"
    var currentTarget: Int? = nil
    let onSelect: (TOCEntry) -> Void
    let onClose: () -> Void

    @AppStorage("reader.theme") private var themeRaw = "light"
    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .light }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .frame(width: 280)
        // 整块侧边栏（含头部）跟随阅读主题变色；与 AIPanelView 同一处理
        .background(theme.panelBg, ignoresSafeAreaEdges: [.horizontal, .bottom])
        .animation(nil, value: themeRaw)
    }

    // MARK: - 头部（样式对齐 AIPanelView）

    private var header: some View {
        HStack(spacing: 10) {
            Text("目录")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    // 图标保持小巧，可点区域给足（原来 11pt 裸图标几乎点不中）
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - 条目列表

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        TOCRow(entry: entry, isCurrent: entry.target == currentTarget) {
                            onSelect(entry)
                            #if os(iOS)
                            // 小屏：跳完章节自动收起目录（macOS 屏幕宽，保持展开）
                            onClose()
                            #endif
                        }
                        .id(entry.target)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onAppear {
                // 打开时滚到当前阅读位置
                if let currentTarget {
                    proxy.scrollTo(currentTarget, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "book.pages")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// 目录行：衬线标题 + 行尾小字，当前项圆角浅底高亮（不用 checkmark）
private struct TOCRow: View {
    let entry: TOCEntry
    let isCurrent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(entry.title)
                    .font(.system(size: 13.5, weight: isCurrent ? .medium : .regular, design: .serif))
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 10 + CGFloat(entry.level) * 14)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor.opacity(0.08)
                          : Color.primary.opacity(hovering ? 0.04 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// PDF 目录提取：优先书签 outline；没有就扫每页文本识别章节标题
///（扫描版 PDF 导入时 Vision OCR 已加文字层，page.string 可读）
enum PDFTOC {
    static func extract(from doc: PDFDocument) -> [TOCEntry] {
        let outline = extractOutline(from: doc)
        return outline.isEmpty ? extractFromText(doc: doc) : outline
    }

    // 书签目录：递归拍平 outline 树，target 为页码
    private static func extractOutline(from doc: PDFDocument) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        func walk(_ outline: PDFOutline, level: Int) {
            for i in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: i) else { continue }
                if let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !label.isEmpty,
                   let page = child.destination?.page {
                    let pageIndex = doc.index(for: page)
                    entries.append(TOCEntry(title: label, level: level,
                                            target: pageIndex, detail: "\(pageIndex + 1)"))
                }
                walk(child, level: level + 1)
            }
        }
        if let root = doc.outlineRoot { walk(root, level: 0) }
        return entries
    }

    // 文本扫描兜底：逐页逐行匹配章节正则，按章节前缀分组。
    // 印刷目录页通常有完整标题（含副标题），正文里的页码更准——各取所长：
    // 标题取组内最长，页码取首个非目录页出现处（一页命中 ≥4 行视为目录页）
    private static func extractFromText(doc: PDFDocument) -> [TOCEntry] {
        struct Hit { let title: String; let page: Int; let line: Int; let key: String }
        var hits: [Hit] = []
        var pageHitCount: [Int: Int] = [:]
        for p in 0..<doc.pageCount {
            guard let text = doc.page(at: p)?.string else { continue }
            var lineNo = 0
            for line in text.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if TXTChapters.isChapterTitle(t), let key = TXTChapters.chapterKey(of: t) {
                    hits.append(Hit(title: t, page: p, line: lineNo, key: key))
                    pageHitCount[p, default: 0] += 1
                }
                lineNo += 1
            }
        }
        func onTOCPage(_ h: Hit) -> Bool { (pageHitCount[h.page] ?? 0) >= 4 }
        var groups: [String: [Hit]] = [:]
        for h in hits { groups[h.key, default: []].append(h) }
        var entries: [TOCEntry] = []
        for g in groups.values {
            let sorted = g.sorted { ($0.page, $0.line) < ($1.page, $1.line) }
            let body = sorted.first { !onTOCPage($0) } ?? sorted[0]
            let fullTitle = g.max { $0.title.count < $1.title.count }?.title ?? body.title
            entries.append(TOCEntry(title: String(fullTitle.prefix(40)), level: 0,
                                    target: body.page, detail: "\(body.page + 1)"))
        }
        return entries.sorted { $0.target < $1.target }
    }
}
