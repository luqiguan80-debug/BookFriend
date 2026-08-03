#if os(macOS)
import SwiftUI
import SwiftData
import WebKit

struct MacEPUBReaderView: View {
    let book: Book
    let modelContext: ModelContext

    @State private var vm: MacEPUBViewModel?
    @State private var loadError: String?
    @State private var showTOC = false
    @State private var showFontPanel = false
    @State private var aiRequest: AIRequest?
    @State private var showAnnotation = false
    @AppStorage("reader.theme") private var theme: ReaderTheme = .light

    var body: some View {
        content
            .navigationTitle(vm?.currentChapter.title ?? "")
            .toolbar {
                ToolbarItem { Button { withAnimation { showTOC.toggle() } } label: { Image(systemName: "list.bullet") } }
                ToolbarItem { NavigationLink(destination: NotesListView(book: book)) { Image(systemName: "note.text") } }
                ToolbarItem { Button { theme = theme.next } label: { Image(systemName: theme.icon) } }
            }
            .sheet(isPresented: $showAnnotation) {
                if let vm {
                    AnnotationPopover(selectedText: vm.selection?.text ?? "",
                        onSave: { note in vm.performHighlight(note: note); showAnnotation = false },
                        onCancel: { showAnnotation = false })
                }
            }
            .task { loadEPUB() }
    }

    private var readerBody: some View {
        VStack(spacing: 0) {
            if let loadError {
                ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let vm {
                ZStack(alignment: .bottom) {
                    MacWKWebView(vm: vm, theme: theme)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.clearSelection() }
                    if vm.selection != nil {
                        selectionToolbar(vm: vm)
                    }
                }
                VStack(spacing: 0) {
                    Hairline()
                    HStack {
                        Button(action: vm.prevChapter) { Label("上一章", systemImage: "chevron.left") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                            .disabled(vm.chapterIndex == 0)
                        Spacer()
                        Text("\(vm.chapterIndex + 1) / \(vm.epub.chapters.count)")
                            .font(.system(.footnote, design: .serif)).foregroundStyle(.tertiary)
                        Spacer()
                        Button(action: vm.nextChapter) { Label("下一章", systemImage: "chevron.right") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                            .disabled(vm.chapterIndex >= vm.epub.chapters.count - 1)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .background(theme.panelBg)
            } else { ProgressView("正在解析…") }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            if showTOC {
                TOCSidebar(entries: (vm?.epub.chapters ?? []).indices.map {
                               TOCEntry(title: vm?.epub.chapters[$0].title ?? "", level: 0, target: $0)
                           },
                           currentTarget: vm?.chapterIndex,
                           onSelect: { vm?.goToChapter($0.target) },
                           onClose: { withAnimation { showTOC = false } })
                    .transition(.move(edge: .leading))
                Hairline(true)
            }
            readerBody.layoutPriority(1)
            if let req = aiRequest {
                Hairline(true)
                AIPanelView(request: req, onClose: { aiRequest = nil }).id(req.id).environmentObject(AISettings()).frame(width: 360)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { vm?.clearSelection() }
    }

    private func loadEPUB() {
        Task.detached(priority: .userInitiated) {
            do {
                let epub = try EPUBParser().parse(epubFile: book.fileURL, extractTo: Storage.extractedDir(for: book.id))
                await MainActor.run {
                    self.vm = MacEPUBViewModel(book: book, epub: epub, modelContext: modelContext)
                }
            } catch {
                await MainActor.run { self.loadError = error.localizedDescription }
            }
        }
    }

    private func selectionToolbar(vm: MacEPUBViewModel) -> some View {
        SelectionActionBar(
            onExplain: { dispatchAI(.explain, vm) },
            onTranslate: { dispatchAI(.translate, vm) },
            onExpand: { dispatchAI(.expand, vm) },
            onHighlight: { showAnnotation = true }
        )
    }

    private func dispatchAI(_ action: NoteType, _ vm: MacEPUBViewModel) {
        guard let p = vm.makeAIPayload() else { return }
        vm.clearSelection()
        aiRequest = AIRequest(action: action, payload: p)
    }
}

// MARK: - macOS WKWebView

struct MacWKWebView: NSViewRepresentable {
    @ObservedObject var vm: MacEPUBViewModel
    var theme: ReaderTheme = .light

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm, theme: theme) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "shuyou")
        config.userContentController.addUserScript(WKUserScript(source: ReaderJS.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let cssLiteral = (try? JSONSerialization.data(withJSONObject: [ReaderJS.css])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        config.userContentController.addUserScript(WKUserScript(source: "(function(){var s=document.createElement('style');s.textContent=\(cssLiteral)[0];document.head.appendChild(s);})();", injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        // ⚠️ key: load the chapter after webView is created
        wv.loadFileURL(vm.currentChapter.url, allowingReadAccessTo: vm.epub.rootDir)
        vm.webView = wv
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.applyTheme(nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let vm: MacEPUBViewModel
        var theme: ReaderTheme
        init(vm: MacEPUBViewModel, theme: ReaderTheme) { self.vm = vm; self.theme = theme }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                webView.evaluateJavaScript("SY.setFontSize(\(vm.fontSize));", completionHandler: nil)
                applyTheme(webView)
                // 恢复滚动位置
                if self.vm.book.scrollOffset > 0 {
                    webView.evaluateJavaScript("window.scrollTo(0, \(self.vm.book.scrollOffset));", completionHandler: nil)
                }
            }
        }

        func applyTheme(_ webView: WKWebView) {
            let js: String
            switch theme {
            case .green:
                js = "document.body.style.background='#CCE8CF';document.body.style.color='#1A2E1A';"
            case .light:
                js = "document.body.style.background='#FBF9F4';document.body.style.color='#2B2B2B';"
            }
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ uc: WKUserContentController, didReceive msg: WKScriptMessage) {
            guard msg.name == "shuyou", let body = msg.body as? [String: Any] else { return }
            // 滚动位置保存
            if body["type"] as? String == "scroll", let y = body["y"] as? Double {
                Task { @MainActor in self.vm.saveScrollOffset(y) }
                return
            }
            Task { @MainActor in
                let text = body["text"] as? String ?? ""
                if text.isEmpty { self.vm.selection = nil }
                else {
                    let rect = body["rect"] as? [String: Double]
                    self.vm.selection = SelectionState(text: text, context: body["context"] as? String ?? "", offset: body["start"] as? Int ?? 0, rectY: CGFloat(rect?["top"] ?? 0))
                }
            }
        }
    }
}

@MainActor
final class MacEPUBViewModel: ObservableObject {
    let book: Book; let epub: EPUBBook
    @Published var chapterIndex: Int; @Published var fontSize: Int
    @Published var selection: SelectionState?
    weak var webView: WKWebView?
    private let modelContext: ModelContext

    init(book: Book, epub: EPUBBook, modelContext: ModelContext) {
        self.book = book; self.epub = epub; self.modelContext = modelContext
        self.chapterIndex = min(book.progressLocation, max(0, epub.chapters.count - 1))
        self.fontSize = 18
    }
    var currentChapter: EPUBChapter { epub.chapters[chapterIndex] }
    func goToChapter(_ i: Int) {
        guard epub.chapters.indices.contains(i) else { return }
        chapterIndex = i
        saveProgress()
        webView?.loadFileURL(currentChapter.url, allowingReadAccessTo: epub.rootDir)
    }

    func saveScrollOffset(_ y: Double) {
        guard abs(y - book.scrollOffset) > 80 else { return }
        book.scrollOffset = y
        book.lastReadAt = .now
        try? modelContext.save()
    }

    private func saveProgress() {
        book.progressLocation = chapterIndex
        book.scrollOffset = 0   // 换章后回到页首，避免 didFinish 误恢复旧章节位置
        book.progressFraction = epub.chapters.count > 1
            ? Double(chapterIndex) / Double(epub.chapters.count - 1) : 1
        book.lastReadAt = .now
        try? modelContext.save()
    }
    func nextChapter() { goToChapter(chapterIndex + 1) }
    func prevChapter() { goToChapter(chapterIndex - 1) }
    func applyFontSize(_ s: Int) { fontSize = s; webView?.evaluateJavaScript("SY.setFontSize(\(s));", completionHandler: nil) }
    func clearSelection() { selection = nil; webView?.evaluateJavaScript("SY.clearSelection();", completionHandler: nil) }
    func performHighlight(note: String = "") {
        guard let s = selection else { return }
        webView?.evaluateJavaScript("SY.highlightSelection('rgba(255,213,79,0.55)');", completionHandler: nil)
        let card = NoteCard(bookID: book.id, bookTitle: book.title, chapterIndex: chapterIndex, chapterTitle: currentChapter.title, type: .highlight, sourceText: s.text, contextText: s.context, resultText: note, offsetInChapter: s.offset)
        modelContext.insert(card); try? modelContext.save()
        selection = nil
    }
    func makeAIPayload() -> SelectionPayload? {
        guard let s = selection else { return nil }
        return SelectionPayload(text: s.text, context: s.context, offset: s.offset, bookID: book.id, bookTitle: book.title, author: book.author, chapterIndex: chapterIndex, chapterTitle: currentChapter.title)
    }
}
#endif
