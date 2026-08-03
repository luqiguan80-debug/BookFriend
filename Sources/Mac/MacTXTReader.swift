#if os(macOS)
import SwiftUI
import AppKit

/// macOS 原生 TXT 阅读器
struct MacTXTReaderView: View {
    let book: Book
    @State private var currentSelection: String?
    @State private var currentContext: String = ""
    @State private var aiRequest: AIRequest?
    @State private var showAnnotation = false
    @State private var tocEntries: [TOCEntry] = []
    @State private var jumpToOffset: Int?
    @State private var showTOC = false
    @AppStorage("reader.theme") private var themeRaw = "light"
    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .light }

    var body: some View {
        HStack(spacing: 0) {
            if showTOC {
                TOCSidebar(entries: tocEntries, emptyText: "未识别到章节结构",
                           onSelect: { jumpToOffset = $0.target },
                           onClose: { withAnimation { showTOC = false } })
                    .transition(.move(edge: .leading))
                Hairline(true)
            }
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    MacTXTView(book: book, selection: $currentSelection, context: $currentContext, theme: theme, toc: $tocEntries, jumpToOffset: $jumpToOffset)
                        .contentShape(Rectangle())
                        .onTapGesture { currentSelection = nil }
                    if currentSelection != nil { selectionToolbar(currentSelection ?? "") }
                }
            }
            .layoutPriority(1)
            if let req = aiRequest {
                Hairline(true)
                AIPanelView(request: req, onClose: { aiRequest = nil }).id(req.id).environmentObject(AISettings()).frame(width: 360)
            }
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem { Button { withAnimation { showTOC.toggle() } } label: { Image(systemName: "list.bullet") } }
            ToolbarItem { Button { themeRaw = theme.next.rawValue } label: { Image(systemName: theme.icon) } }
            ToolbarItem { NavigationLink(destination: NotesListView(book: book)) { Image(systemName: "note.text") } }
        }
        .sheet(isPresented: $showAnnotation) {
            AnnotationPopover(selectedText: currentSelection ?? "",
                onSave: { note in saveHighlight(currentSelection ?? "", note: note); showAnnotation = false },
                onCancel: { showAnnotation = false })
        }
    }

    private func selectionToolbar(_ text: String) -> some View {
        SelectionActionBar(
            onExplain: { dispatch(.explain, text) },
            onTranslate: { dispatch(.translate, text) },
            onExpand: { dispatch(.expand, text) },
            onHighlight: { showAnnotation = true }
        )
    }

    private func dispatch(_ action: NoteType, _ text: String) {
        let p = SelectionPayload(text:text, context:currentContext, offset:0, bookID:book.id, bookTitle:book.title, author:book.author, chapterIndex:0, chapterTitle:"")
        currentSelection = nil
        aiRequest = AIRequest(action: action, payload: p)
    }

    private func saveHighlight(_ text: String, note: String) {
        let card = NoteCard(bookID:book.id, bookTitle:book.title, chapterIndex:0, chapterTitle:"", type:.highlight, sourceText:text, resultText: note)
        let ctx = SelectionCenter.shared.modelContext; ctx?.insert(card); try? ctx?.save()
        currentSelection = nil
    }
}

struct MacTXTView: NSViewRepresentable {
    let book: Book
    @Binding var selection: String?
    @Binding var context: String
    var theme: ReaderTheme = .light
    @Binding var toc: [TOCEntry]
    @Binding var jumpToOffset: Int?

    func makeCoordinator() -> Coordinator { Coordinator(sel: $selection, ctx: $context, book: book) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.pdfBg
        let tv = NSTextView()
        tv.isEditable = false; tv.isSelectable = true
        tv.font = .systemFont(ofSize: 16)
        tv.textContainerInset = NSSize(width: 24, height: 24)
        tv.backgroundColor = theme.pdfBg
        if let data = try? Data(contentsOf: book.fileURL),
           let content = String(data: data, encoding: .utf8) {
            tv.string = content
            // 启发式识别章节标题，回写给目录弹层
            let entries = TXTChapters.detect(in: content)
            DispatchQueue.main.async { toc = entries }
        }
        scrollView.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.scrollView = scrollView
        // 恢复滚动位置
        if book.scrollOffset > 0 {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: book.scrollOffset))
        }
        // 监听滚动保存
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.backgroundColor = theme.pdfBg
        context.coordinator.textView?.backgroundColor = theme.pdfBg
        // 目录跳转：目标章节行滚到顶部，然后清除请求
        if let offset = jumpToOffset, let tv = context.coordinator.textView,
           let layoutManager = tv.layoutManager, let textContainer = tv.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let glyph = layoutManager.glyphIndexForCharacter(at: offset)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            tv.scroll(NSPoint(x: 0, y: rect.minY - 8))
            DispatchQueue.main.async { jumpToOffset = nil }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var selection: String?
        @Binding var context: String
        let book: Book
        weak var textView: NSTextView? { didSet { textView?.delegate = self } }
        weak var scrollView: NSScrollView?
        private var lastY: Double = 0

        init(sel: Binding<String?>, ctx: Binding<String>, book: Book) { _selection = sel; _context = ctx; self.book = book; super.init() }

        @objc func scrollDidChange(_ n: Notification) {
            guard let clipView = n.object as? NSClipView else { return }
            let y = clipView.bounds.origin.y
            if abs(y - lastY) > 50 {
                lastY = y
                // 滚动进度 = 已滚距离 / 可滚总距离
                let docH = clipView.documentView?.frame.height ?? 0
                let scrollable = docH - clipView.bounds.height
                let fraction = scrollable > 0 ? min(1, max(0, y / scrollable)) : 1
                Task { @MainActor in
                    book.scrollOffset = y
                    book.progressFraction = fraction
                    book.lastReadAt = .now
                    try? SelectionCenter.shared.modelContext?.save()
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView, let range = tv.selectedRanges.first as? NSRange, range.length > 0
            else { Task { @MainActor in selection = nil; context = "" }; return }
            let text = (tv.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { Task { @MainActor in selection = nil; context = "" }; return }
            let ctx = SelectionContext.around(range, in: tv.string)
            Task { @MainActor in selection = text; context = ctx }
        }
    }
}
#endif
