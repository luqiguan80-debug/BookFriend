#if os(iOS)
import SwiftUI
import UIKit
import SwiftData

struct TXTReaderView: View {
    let book: Book
    @State private var selectionText: String?
    @State private var selectionContext: String = ""
    @State private var selectionOffset: Int = 0
    @State private var aiRequest: AIRequest?
    @State private var showAnnotation = false
    @State private var tocEntries: [TOCEntry] = []
    @State private var jumpToOffset: Int?
    @State private var showTOC = false
    @State private var showFontPanel = false
    // 与 EPUB 阅读器共用同一字号设置
    @AppStorage("reader.fontSize") private var fontSize = 18

    var body: some View {
        HStack(spacing: 0) {
            if showTOC {
                TOCSidebar(entries: tocEntries, emptyText: "未识别到章节结构",
                           onSelect: { jumpToOffset = $0.target },
                           onClose: { withAnimation { showTOC = false } })
                    .transition(.move(edge: .leading))
                Hairline(true)
            }
            ZStack {
                TXTTextView(book: book, selectionText: $selectionText,
                            selectionContext: $selectionContext, selectionOffset: $selectionOffset,
                            toc: $tocEntries, jumpToOffset: $jumpToOffset, fontSize: fontSize)

                if selectionText != nil {
                    VStack {
                        Spacer()
                        selectionToolbar
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 字号调节面板（选中文字时让位给动作条）
                if showFontPanel && selectionText == nil {
                    VStack {
                        Spacer()
                        HStack {
                            Text("A").font(.system(size: 14))
                            Slider(value: Binding(
                                get: { Double(fontSize) },
                                set: { fontSize = Int($0) }
                            ), in: 13...32, step: 1)
                            Text("A").font(.system(size: 24))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.bar)
                    }
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { withAnimation { showTOC.toggle() } } label: { Image(systemName: "list.bullet") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: NotesListView(book: book)) {
                    Image(systemName: "note.text")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation { showFontPanel.toggle() } } label: { Image(systemName: "textformat.size") }
            }
        }
        .sheet(isPresented: $showAnnotation) {
            AnnotationPopover(selectedText: selectionText ?? "",
                onSave: { note in saveHighlight(selectionText ?? "", note: note); showAnnotation = false },
                onCancel: { showAnnotation = false })
        }
        .sheet(item: $aiRequest) { request in
            AIPanelView(request: request)
                .environmentObject(AISettings())
        }
    }

    private var selectionToolbar: some View {
        SelectionActionBar(
            onExplain: { dispatchAI(.explain) },
            onTranslate: { dispatchAI(.translate) },
            onExpand: { dispatchAI(.expand) },
            onHighlight: { showAnnotation = true },
            onClose: { selectionText = nil }
        )
    }

    private func dispatchAI(_ action: NoteType) {
        guard let text = selectionText else { return }
        let payload = SelectionPayload(text: text, context: selectionContext,
            offset: selectionOffset, bookID: book.id, bookTitle: book.title,
            author: book.author, chapterIndex: 0, chapterTitle: "")
        selectionText = nil
        aiRequest = AIRequest(action: action, payload: payload)
    }

    private func saveHighlight(_ text: String, note: String) {
        let card = NoteCard(bookID: book.id, bookTitle: book.title, chapterIndex: 0, chapterTitle: "", type: .highlight, sourceText: text, resultText: note)
        let ctx = SelectionCenter.shared.modelContext; ctx?.insert(card); try? ctx?.save()
        selectionText = nil
    }
}

// MARK: - UITextView 封装

struct TXTTextView: UIViewRepresentable {
    let book: Book
    @Binding var selectionText: String?
    @Binding var selectionContext: String
    @Binding var selectionOffset: Int
    @Binding var toc: [TOCEntry]
    @Binding var jumpToOffset: Int?
    var fontSize: Int = 18

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.font = .systemFont(ofSize: CGFloat(fontSize))
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 18, bottom: 200, right: 18)
        textView.textContainer.lineFragmentPadding = 4
        if let data = try? Data(contentsOf: book.fileURL),
           let content = String(data: data, encoding: .utf8) ?? decodeGB18030(data) {
            textView.text = content
            // 启发式识别章节标题，回写给目录弹层
            let entries = TXTChapters.detect(in: content)
            DispatchQueue.main.async { toc = entries }
            // 恢复上次滚动位置（等布局完成后再跳）
            if book.scrollOffset > 0 {
                let y = book.scrollOffset
                DispatchQueue.main.async {
                    textView.layoutManager.ensureLayout(for: textView.textContainer)
                    textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                }
            }
        } else {
            textView.text = "（无法读取文件内容）"
        }
        context.coordinator.observe(textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // 字号实时生效
        if uiView.font?.pointSize != CGFloat(fontSize) {
            uiView.font = .systemFont(ofSize: CGFloat(fontSize))
        }
        // 目录跳转：目标章节行滚到顶部，然后清除请求
        if let offset = jumpToOffset {
            uiView.layoutManager.ensureLayout(for: uiView.textContainer)
            let glyph = uiView.layoutManager.glyphIndexForCharacter(at: offset)
            let rect = uiView.layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: uiView.textContainer)
            uiView.setContentOffset(CGPoint(x: 0, y: rect.minY - 8), animated: false)
            DispatchQueue.main.async { jumpToOffset = nil }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(book: book, selectionText: $selectionText, selectionContext: $selectionContext, selectionOffset: $selectionOffset)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let book: Book
        @Binding var selectionText: String?
        @Binding var selectionContext: String
        @Binding var selectionOffset: Int
        private var lastY: CGFloat = 0

        init(book: Book, selectionText: Binding<String?>, selectionContext: Binding<String>, selectionOffset: Binding<Int>) {
            self.book = book
            _selectionText = selectionText
            _selectionContext = selectionContext
            _selectionOffset = selectionOffset
            super.init()
        }

        func observe(_ textView: UITextView) {
            textView.delegate = self
        }

        // 滚动进度 = 已滚距离 / 可滚总距离（书架进度条）
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            guard abs(y - lastY) > 50 else { return }
            lastY = y
            let scrollable = scrollView.contentSize.height - scrollView.bounds.height
            book.scrollOffset = Double(y)
            book.progressFraction = scrollable > 0 ? min(1, max(0, Double(y / scrollable))) : 1
            book.lastReadAt = .now
            try? SelectionCenter.shared.modelContext?.save()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange,
                  let text = textView.text(in: range)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                selectionText = nil
                selectionContext = ""
                return
            }
            selectionOffset = textView.offset(from: textView.beginningOfDocument, to: range.start)
            selectionContext = SelectionContext.around(textView.selectedRange, in: textView.text)
            selectionText = text
        }
    }

    private func decodeGB18030(_ data: Data) -> String? {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        return String(data: data, encoding: encoding)
    }
}
#endif
