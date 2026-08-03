#if os(macOS)
import SwiftUI
import PDFKit

struct MacPDFReaderView: View {
    let book: Book
    @EnvironmentObject var settings: AISettings
    @State private var currentSelection: String?
    @State private var currentContext: String = ""
    @State private var currentPage = 0
    @State private var aiRequest: AIRequest?
    @State private var showAnnotation = false
    @State private var tocEntries: [TOCEntry] = []
    @State private var jumpToPage: Int?
    @State private var showTOC = false
    @AppStorage("reader.theme") private var themeRaw = "light"

    var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .light }

    var body: some View {
        HStack(spacing: 0) {
            if showTOC {
                TOCSidebar(entries: tocEntries, emptyText: "这本书没有可识别的目录",
                           currentTarget: currentPage,
                           onSelect: { jumpToPage = $0.target },
                           onClose: { withAnimation { showTOC = false } })
                    .transition(.move(edge: .leading))
                Hairline(true)
            }
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    MacPDFKitView(book: book, selection: $currentSelection, context: $currentContext, page: $currentPage, theme: theme, toc: $tocEntries, jumpToPage: $jumpToPage)
                        .contentShape(Rectangle())
                        .onTapGesture { currentSelection = nil }
                    if currentSelection != nil { selectionToolbar(currentSelection ?? "") }
                }
            }
            .layoutPriority(1)
            if let req = aiRequest {
                Hairline(true)
                AIPanelView(request: req, onClose: { aiRequest = nil }).id(req.id).environmentObject(settings).frame(width: 360)
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
        let p = SelectionPayload(text:text, context:currentContext, offset:0, bookID:book.id, bookTitle:book.title, author:book.author, chapterIndex:currentPage, chapterTitle:"第 \(currentPage+1) 页")
        currentSelection = nil
        aiRequest = AIRequest(action: action, payload: p)
    }

    private func saveHighlight(_ text: String, note: String) {
        let card = NoteCard(bookID:book.id, bookTitle:book.title, chapterIndex:currentPage, chapterTitle:"第 \(currentPage+1) 页", type:.highlight, sourceText:text, resultText: note)
        let ctx = SelectionCenter.shared.modelContext; ctx?.insert(card); try? ctx?.save()
        currentSelection = nil
    }
}

struct MacPDFKitView: NSViewRepresentable {
    let book: Book
    @Binding var selection: String?
    @Binding var context: String
    @Binding var page: Int
    var theme: ReaderTheme = .light
    @Binding var toc: [TOCEntry]
    @Binding var jumpToPage: Int?

    func makeCoordinator() -> Coordinator { Coordinator(sel: $selection, ctx: $context, page: $page, book: book) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let pv = PDFView()
        pv.displayMode = .singlePageContinuous
        pv.displayDirection = .vertical
        pv.autoScales = true
        pv.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        pv.displayBox = .cropBox
        // 页间缝隙用白色：正常模式白底，护眼模式由染色层统一染绿
        pv.backgroundColor = .white
        if let doc = PDFDocument(url: book.fileURL) {
            pv.document = doc
            // 恢复上次阅读位置
            if book.progressLocation > 0,
               let pg = doc.page(at: min(book.progressLocation, doc.pageCount - 1)) {
                pv.go(to: pg)
            }
            // 提取书签目录（outline），回写给目录弹层
            let entries = PDFTOC.extract(from: doc)
            DispatchQueue.main.async { toc = entries }
        }
        pv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pv)

        // 主题染色层：multiply 混合（白底→主题色、黑字不变）。
        // 切主题只改图层颜色，不重绘 PDF 页，瞬时完成
        let tint = MultiplyTintView()
        tint.layer?.backgroundColor = theme.pdfBg.cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tint)

        NSLayoutConstraint.activate([
            pv.topAnchor.constraint(equalTo: container.topAnchor),
            pv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tint.topAnchor.constraint(equalTo: container.topAnchor),
            tint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.pdfView = pv
        context.coordinator.tintView = tint
        context.coordinator.startObserving(pv)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 浅色主题 pdfBg 为白色，multiply 后恒等，无需隐藏染色层
        context.coordinator.tintView?.layer?.backgroundColor = theme.pdfBg.cgColor
        // 目录跳转：跳到目标页后清除请求
        if let target = jumpToPage,
           let pg = context.coordinator.pdfView?.document?.page(at: target) {
            context.coordinator.pdfView?.go(to: pg)
            DispatchQueue.main.async { jumpToPage = nil }
        }
    }

    final class Coordinator: NSObject {
        @Binding var selection: String?
        @Binding var context: String
        @Binding var page: Int
        let book: Book
        weak var pdfView: PDFView?
        weak var tintView: MultiplyTintView?
        private var pollTimer: Timer?
        private var lastValidSelection: String?

        init(sel: Binding<String?>, ctx: Binding<String>, page: Binding<Int>, book: Book) {
            _selection = sel
            _context = ctx
            _page = page
            self.book = book
            super.init()
        }

        func startObserving(_ pdfView: PDFView) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(selectionDidChange),
                name: .PDFViewSelectionChanged, object: pdfView)
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageDidChange),
                name: .PDFViewPageChanged, object: pdfView)
        }

        @objc private func pageDidChange(_ n: Notification) {
            guard let pv = n.object as? PDFView,
                  let doc = pv.document,
                  let pg = pv.currentPage else { return }
            let idx = doc.index(for: pg)
            let pageCount = doc.pageCount
            Task { @MainActor in
                page = idx
                // 记录阅读进度（书架进度条 + 下次恢复页码）
                book.progressLocation = idx
                book.progressFraction = pageCount > 1 ? Double(idx) / Double(pageCount - 1) : 1
                book.lastReadAt = .now
                try? SelectionCenter.shared.modelContext?.save()
            }
        }

        @objc private func selectionDidChange(_ n: Notification) {
            guard let pv = n.object as? PDFView else { return }
            let text = validatedSelection(from: pv)
            Task { @MainActor in
                if let text, !text.isEmpty {
                    lastValidSelection = text
                    // 取选段所在页前后各 500 字作为上下文
                    if let sel = pv.currentSelection, let pg = sel.pages.first, let pageText = pg.string {
                        context = SelectionContext.around(sel.range(at: 0, on: pg), in: pageText)
                    }
                    selection = text
                } else if pv.currentSelection == nil {
                    // 用户点了空白处，选段已清除 → 关闭工具栏
                    lastValidSelection = nil
                    selection = nil
                    context = ""
                }
                // 选段被过滤（整页误选等）→ 保持现状不动
            }
        }

        private func validatedSelection(from pdfView: PDFView) -> String? {
            guard let sel = pdfView.currentSelection else { return nil }
            guard sel.pages.count <= 1 else { return nil }
            let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.count >= 2 else { return nil }
            if let page = sel.pages.first, let pageText = page.string {
                let ratio = Double(text.count) / Double(max(pageText.count, 1))
                if ratio > 0.85 { return nil }
            }
            return text
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            pollTimer?.invalidate()
        }
    }
}

/// 覆盖在 PDFView 上的主题染色层：multiply 混合把白底染成主题色、黑字保持不变。
/// 效果等同逐页重绘 multiply，但切换主题零重绘。不拦截鼠标事件。
final class MultiplyTintView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.compositingFilter = "multiplyBlendMode"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
