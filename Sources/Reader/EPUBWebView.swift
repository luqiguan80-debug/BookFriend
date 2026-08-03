#if os(iOS)
import SwiftUI
import WebKit
import SwiftData

// MARK: - 选段状态（JS → Swift）
// SelectionState 统一在 SelectionCenter.swift 定义（iOS/macOS 共用）

@MainActor
final class EPUBViewModel: ObservableObject {
    let book: Book
    let epub: EPUBBook
    @Published var chapterIndex: Int
    @Published var fontSize: Int
    @Published var chapterCards: [NoteCard] = []
    @Published var selection: SelectionState?
    /// 首次渲染后恢复章节内滚动位置，只恢复一次
    private var didRestoreScroll = false

    weak var webView: WKWebView?
    private let modelContext: ModelContext

    init(book: Book, epub: EPUBBook, modelContext: ModelContext) {
        self.book = book
        self.epub = epub
        self.modelContext = modelContext
        self.chapterIndex = min(book.progressLocation, max(0, epub.chapters.count - 1))
        self.fontSize = UserDefaults.standard.object(forKey: "reader.fontSize") as? Int ?? 18
    }

    var currentChapter: EPUBChapter { epub.chapters[chapterIndex] }

    func loadCurrentChapter() {
        guard let webView else { return }
        webView.loadFileURL(currentChapter.url, allowingReadAccessTo: epub.rootDir)
        refreshChapterCards()
    }

    func goToChapter(_ index: Int) {
        guard epub.chapters.indices.contains(index) else { return }
        chapterIndex = index
        saveProgress()
        loadCurrentChapter()
    }

    func nextChapter() { goToChapter(chapterIndex + 1) }
    func prevChapter() { goToChapter(chapterIndex - 1) }

    func applyFontSize(_ size: Int) {
        fontSize = size
        UserDefaults.standard.set(size, forKey: "reader.fontSize")
        webView?.evaluateJavaScript("SY.setFontSize(\(size));", completionHandler: nil)
    }

    // 清除选择
    func clearSelection() {
        selection = nil
        webView?.evaluateJavaScript("SY.clearSelection();", completionHandler: nil)
    }

    private func saveProgress() {
        book.progressLocation = chapterIndex
        book.scrollOffset = 0   // 换章后回到页首，清掉旧章节内的滚动位置
        book.progressFraction = epub.chapters.count > 1
            ? Double(chapterIndex) / Double(epub.chapters.count - 1) : 1
        book.lastReadAt = .now
        try? modelContext.save()
    }

    // 章节内滚动位置（JS scroll 消息回调，变化够大才落盘）
    func saveScrollOffset(_ y: Double) {
        guard abs(y - book.scrollOffset) > 80 else { return }
        book.scrollOffset = y
        book.lastReadAt = .now
        try? modelContext.save()
    }

    // MARK: - 划线重绘

    private func refreshChapterCards() {
        let bookID = book.id
        let index = chapterIndex
        let predicate = #Predicate<NoteCard> {
            $0.bookID == bookID && $0.chapterIndex == index && $0.typeRaw == "highlight"
        }
        let descriptor = FetchDescriptor<NoteCard>(predicate: predicate)
        chapterCards = (try? modelContext.fetch(descriptor)) ?? []
    }

    func onChapterRendered() {
        webView?.evaluateJavaScript("SY.setFontSize(\(fontSize));", completionHandler: nil)
        // 恢复上次读到本章内的位置（仅首次打开时一次）
        if !didRestoreScroll {
            didRestoreScroll = true
            if book.scrollOffset > 0 {
                webView?.evaluateJavaScript("window.scrollTo(0, \(book.scrollOffset));", completionHandler: nil)
            }
        }
        for card in chapterCards {
            let js = "SY.markByOffset(\(Self.jsString(card.sourceText)), \(card.offsetInChapter), 'rgba(255,213,79,0.55)');"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - 动作执行

    func performHighlight(note: String = "") {
        guard let sel = selection else { return }
        webView?.evaluateJavaScript("SY.highlightSelection('rgba(255,213,79,0.55)');", completionHandler: nil)
        let card = NoteCard(
            bookID: book.id, bookTitle: book.title,
            chapterIndex: chapterIndex, chapterTitle: currentChapter.title,
            type: .highlight, sourceText: sel.text, contextText: sel.context,
            resultText: note, offsetInChapter: sel.offset
        )
        modelContext.insert(card)
        try? modelContext.save()
        selection = nil
    }

    func makeAIPayload() -> SelectionPayload? {
        guard let sel = selection else { return nil }
        return SelectionPayload(
            text: sel.text, context: sel.context, offset: sel.offset,
            bookID: book.id, bookTitle: book.title, author: book.author,
            chapterIndex: chapterIndex, chapterTitle: currentChapter.title
        )
    }

    static func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        return "'\(escaped)'"
    }
}

// MARK: - WKWebView 封装（Catalyst 兼容）

/// 用 UIViewControllerRepresentable 包一层，确保 Mac Catalyst 下滚轮事件正确传递
struct EPUBWebView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: EPUBViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIViewController(context: Context) -> WKScrollViewController {
        let vc = WKScrollViewController()
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "shuyou")
        let js = WKUserScript(source: ReaderJS.source,
                              injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(js)
        let cssLiteral = (try? JSONSerialization.data(withJSONObject: [ReaderJS.css]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        let cssJS = """
        (function() {
            var style = document.createElement('style');
            style.textContent = \(cssLiteral)[0];
            document.head.appendChild(style);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: cssJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.alwaysBounceHorizontal = false
        #if targetEnvironment(macCatalyst)
        webView.scrollView.panGestureRecognizer.allowedScrollTypesMask = .all
        #endif
        vc.attach(webView: webView)
        viewModel.webView = webView
        return vc
    }

    func updateUIViewController(_ uiViewController: WKScrollViewController, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let viewModel: EPUBViewModel
        init(viewModel: EPUBViewModel) { self.viewModel = viewModel }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in self.viewModel.onChapterRendered() }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "shuyou",
                  let body = message.body as? [String: Any] else { return }
            // 滚动位置保存
            if body["type"] as? String == "scroll", let y = body["y"] as? Double {
                Task { @MainActor in self.viewModel.saveScrollOffset(y) }
                return
            }
            Task { @MainActor in
                let text = body["text"] as? String ?? ""
                if text.isEmpty {
                    self.viewModel.selection = nil
                } else {
                    let rect = body["rect"] as? [String: Double]
                    self.viewModel.selection = SelectionState(
                        text: text,
                        context: body["context"] as? String ?? "",
                        offset: body["start"] as? Int ?? 0,
                        rectY: CGFloat(rect?["top"] ?? 0)
                    )
                }
            }
        }
    }
}

// MARK: - WKWebView 宿主 ViewController

/// WKWebView 放在 UIViewController 内，Catalyst 下启滚轮支持
final class WKScrollViewController: UIViewController {
    private var _webView: WKWebView?

    /// makeUIViewController 里调用，确保约束在 view 加载后立即生效
    func attach(webView: WKWebView) {
        _webView = webView
        _ = view // 触发 loadView，之后才能加约束
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        NSLog("[ShuYou] WebView attached, frame=\(view.frame)")
    }
}
#endif
