#if os(iOS)
import SwiftUI
import PDFKit
import SwiftData
import Vision
import UIKit

struct PDFReaderView: View {
    let book: Book
    @EnvironmentObject var settings: AISettings
    @State private var currentSelection: String?
    @State private var currentContext: String = ""
    @State private var currentPage: Int = 0
    @State private var aiRequest: AIRequest?
    @State private var showAnnotation = false
    @State private var tocEntries: [TOCEntry] = []
    @State private var jumpToPage: Int?
    @State private var showTOC = false
    @State private var showFontPanel = false
    @State private var flowResult: PDFReflow.Result?
    @State private var jumpCharOffset: Int?
    @State private var immersive = false
    @State private var flowPageCurrent = 0
    @State private var flowPageTotal = 0

    // 电池信息（状态条用，60s 刷新）
    private var batteryInfo: (icon: String, pct: Int) {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Int((UIDevice.current.batteryLevel * 100).rounded())
        let state = UIDevice.current.batteryState
        let icon: String
        switch state {
        case .charging, .full: icon = "battery.100.bolt"
        case .unplugged: icon = level <= 20 ? "battery.25" : level <= 50 ? "battery.50" : "battery.75"
        default: icon = "battery.50"
        }
        return (icon, max(0, min(100, level)))
        #else
        return ("battery.50", 100)
        #endif
    }
    // 阅读模式排版设置（行距/护眼绿独立存，字号与 EPUB/TXT 共用）
    @AppStorage("reader.lineSpacing") private var lineSpacing = 8.0
    @AppStorage("reader.eyeCare") private var eyeCare = false
    /// 纯文字重排模式（PDF 版式钉死无法改字号，抽文字按 TXT 排版）
    @AppStorage("reader.pdfTextMode") private var textMode = false
    // 与 EPUB/TXT 共用同一字号设置
    @AppStorage("reader.fontSize") private var fontSize = 18

    var body: some View {
        HStack(spacing: 0) {
            if showTOC {
                TOCSidebar(entries: tocEntries, emptyText: "这本书没有可识别的目录",
                           currentTarget: currentPage,
                           onSelect: { entry in
                               if textMode {
                                   // 纯文本模式：页码 → 纯文本字符偏移
                                   let page = min(entry.target, (flowResult?.pageOffsets.count ?? 1) - 1)
                                   if page >= 0 { jumpCharOffset = flowResult?.pageOffsets[page] }
                               } else {
                                   jumpToPage = entry.target
                               }
                           },
                           onClose: { withAnimation { showTOC = false } })
                    .transition(.move(edge: .leading))
                Hairline(true)
            }
            ZStack(alignment: .bottom) {
                if textMode {
                    if let flowResult {
                        PDFFlowTextView(book: book, blocks: flowResult.blocks, fontSize: fontSize,
                                        lineSpacing: lineSpacing, eyeCare: eyeCare,
                                        jumpToOffset: $jumpCharOffset,
                                        selectionText: $currentSelection,
                                        selectionContext: $currentContext,
                                        onTap: toggleImmersive,
                                        onPageChange: { c, t in flowPageCurrent = c; flowPageTotal = t })
                    } else {
                        ProgressView("正在提取文字…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    _PDFKitBridge(book: book,
                                  selectionBinding: $currentSelection,
                                  contextBinding: $currentContext,
                                  pageBinding: $currentPage,
                                  toc: $tocEntries,
                                  jumpToPage: $jumpToPage,
                                  onTap: toggleImmersive)
                }

                if let sel = currentSelection, !sel.isEmpty {
                    selectionToolbar(sel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 排版面板（仅纯文本模式，选中文字时让位，沉浸时也隐藏）：字号 + 行距 + 护眼绿
                if textMode && showFontPanel && currentSelection == nil && !immersive {
                    VStack {
                        Spacer()
                        VStack(spacing: 10) {
                            HStack {
                                Text("A").font(.system(size: 14))
                                Slider(value: Binding(
                                    get: { Double(fontSize) },
                                    set: { fontSize = Int($0) }
                                ), in: 13...32, step: 1)
                                Text("A").font(.system(size: 24))
                            }
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Slider(value: $lineSpacing, in: 2...18, step: 1)
                                Button { eyeCare.toggle() } label: {
                                    Image(systemName: eyeCare ? "leaf.fill" : "leaf")
                                        .font(.system(size: 16))
                                        .foregroundStyle(eyeCare ? Color(red: 0.35, green: 0.6, blue: 0.35) : .secondary)
                                        .frame(width: 32, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("护眼模式")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.bar)
                    }
                }
                // 阅读状态条：时间 + 电量 + 分页 x/y（沉浸时系统状态栏隐藏，由它顶替）
                if textMode && !showFontPanel {
                    VStack(spacing: 0) {
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            HStack(spacing: 6) {
                                let batt = batteryInfo
                                Label("\(batt.pct)%", systemImage: batt.icon)
                                Text(context.date, format: .dateTime.hour().minute())
                                Spacer()
                                if flowPageTotal > 0 {
                                    Text("\(flowPageCurrent)/\(flowPageTotal)")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                        }
                        .background(eyeCare ? Color(red: 0.91, green: 0.94, blue: 0.90) : Color(.systemBackground))
                    }
                    .allowsHitTesting(false)
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
            if textMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { showFontPanel.toggle() } } label: { Image(systemName: "textformat.size") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleTextMode() } label: {
                    Image(systemName: textMode ? "doc.richtext" : "book.pages")
                }
                .help(textMode ? "返回版式视图" : "阅读模式（可调字号行距）")
            }
        }
        .onChange(of: textMode) { _, _ in currentSelection = nil }
        // textMode 持久化：退出再进时已在阅读模式，需要补触发提取，否则永远转圈
        .task { if textMode && flowResult == nil { extractFlowText() } }
        // 沉浸模式：点一下隐藏全部边框（顶部栏/状态栏），文字铺满屏幕；再点恢复。
        // 阅读模式始终铺满底部，否则 home 条露出白边与文字区底色断层
        .toolbar(immersive ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(immersive)
        // 沉浸时全屏，但底部安全区仍要留（曲角 + home 条）；非沉浸时不越界
        .ignoresSafeArea(.container, edges: immersive ? [.top] : [])
        .sheet(isPresented: $showAnnotation) {
            AnnotationPopover(selectedText: currentSelection ?? "",
                onSave: { note in saveHighlight(currentSelection ?? "", note: note); showAnnotation = false },
                onCancel: { showAnnotation = false })
        }
        .sheet(item: $aiRequest) { request in
            AIPanelView(request: request)
                .environmentObject(settings)
        }
        .animation(.easeOut(duration: 0.2), value: currentSelection != nil)
    }

    // MARK: - 动作条

    private func selectionToolbar(_ text: String) -> some View {
        SelectionActionBar(
            onExplain: { dispatchAI(.explain, text) },
            onTranslate: { dispatchAI(.translate, text) },
            onExpand: { dispatchAI(.expand, text) },
            onHighlight: { showAnnotation = true },
            onClose: { currentSelection = nil }
        )
    }

    private func dispatchAI(_ action: NoteType, _ text: String) {
        let payload = SelectionPayload(text: text, context: currentContext,
            offset: 0, bookID: book.id, bookTitle: book.title, author: book.author,
            chapterIndex: textMode ? 0 : currentPage,
            chapterTitle: textMode ? "纯文本" : "第 \(currentPage + 1) 页")
        currentSelection = nil
        aiRequest = AIRequest(action: action, payload: payload)
    }

    private func saveHighlight(_ text: String, note: String = "") {
        let card = NoteCard(
            bookID: book.id, bookTitle: book.title,
            chapterIndex: textMode ? 0 : currentPage,
            chapterTitle: textMode ? "纯文本" : "第 \(currentPage + 1) 页",
            type: .highlight, sourceText: text, resultText: note)
        // 写入 SwiftData
        let ctx = SelectionCenter.shared.modelContext
        ctx?.insert(card)
        try? ctx?.save()
        currentSelection = nil
    }

    // MARK: - 纯文字模式

    private func toggleTextMode() {
        withAnimation { textMode.toggle() }
        if textMode && flowResult == nil { extractFlowText() }
    }

    private func toggleImmersive() {
        withAnimation { immersive.toggle() }
        if immersive { showFontPanel = false }   // 沉浸时连带收掉字号面板
    }

    /// 重排全书文字（WPS 阅读模式式：去页眉页脚 + 段落重组 + 标题识别）
    private func extractFlowText() {
        let url = book.fileURL
        Task.detached(priority: .userInitiated) {
            let result = PDFReflow.extract(from: url)
            await MainActor.run {
                flowResult = result.blocks.isEmpty
                    ? PDFReflow.Result(blocks: [PDFReflow.Block(kind: .paragraph, text: "（未能提取到文字）")],
                                       pageOffsets: [0])
                    : result
            }
        }
    }
}

// MARK: - 纯文字重排视图（字号可调，支持选段唤起 AI）

private struct PDFFlowTextView: UIViewRepresentable {
    let book: Book
    let blocks: [PDFReflow.Block]
    let fontSize: Int
    let lineSpacing: Double
    let eyeCare: Bool
    @Binding var jumpToOffset: Int?
    @Binding var selectionText: String?
    @Binding var selectionContext: String
    var onTap: () -> Void = {}
    var onPageChange: (Int, Int) -> Void = { _, _ in }

    /// 护眼绿：淡灰绿（对齐 WPS 阅读模式，#E8F0E6；原来的豆沙绿太饱和）
    private var bgColor: UIColor {
        eyeCare ? UIColor(red: 0.91, green: 0.94, blue: 0.90, alpha: 1) : .systemBackground
    }

    /// 重排块 → 排版属性串：标题加粗加大，正文衬线 + 首行缩进两字符 + 可调行距
    private func makeAttributedText() -> NSAttributedString {
        let size = CGFloat(fontSize)
        let serifDesc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withDesign(.serif) ?? UIFontDescriptor()
        let bodyFont = UIFont(descriptor: serifDesc, size: size)
        let bodyBoldFont = UIFont(descriptor: serifDesc.withSymbolicTraits(.traitBold) ?? serifDesc, size: size)
        let headFont = UIFont(descriptor: serifDesc.withSymbolicTraits(.traitBold) ?? serifDesc, size: size + 4)

        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineSpacing = CGFloat(lineSpacing)
        bodyPara.paragraphSpacing = 12
        bodyPara.firstLineHeadIndent = size * 2   // 首行缩进两字符

        let headPara = NSMutableParagraphStyle()
        headPara.lineSpacing = 6
        headPara.paragraphSpacingBefore = 20
        headPara.paragraphSpacing = 14

        let out = NSMutableAttributedString()
        for (i, block) in blocks.enumerated() {
            let isHeading = block.kind == .heading
            let attrs: [NSAttributedString.Key: Any] = [
                .font: isHeading ? headFont : (block.bold ? bodyBoldFont : bodyFont),
                .paragraphStyle: isHeading ? headPara : bodyPara,
                .foregroundColor: UIColor.label,
            ]
            out.append(NSAttributedString(string: block.text, attributes: attrs))
            if i < blocks.count - 1 { out.append(NSAttributedString(string: "\n")) }
        }
        return out
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.textContainerInset = UIEdgeInsets(top: 24, left: 18, bottom: 36, right: 18)
        tv.textContainer.lineFragmentPadding = 4
        tv.attributedText = makeAttributedText()
        tv.backgroundColor = bgColor
        tv.isPagingEnabled = false   // 连续滚动，不翻页
        tv.contentInset.bottom = 0   // 安全区已由系统处理
        tv.delegate = context.coordinator
        context.coordinator.appliedFontSize = fontSize
        context.coordinator.appliedLineSpacing = lineSpacing
        context.coordinator.onTap = onTap
        context.coordinator.onPageChange = onPageChange
        // 单击：沉浸/恢复（不拦截 textView 自身触摸，选字不受影响）
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)
        // 恢复上次滚动位置：先隐身，跳到位再淡入（避免「从顶部滑下去」的可见跳动）
        if book.scrollOffset > 0 {
            tv.alpha = 0
            restorePosition(tv, y: book.scrollOffset)
        }
        return tv
    }

    private func restorePosition(_ tv: UITextView, y: CGFloat) {
        DispatchQueue.main.async {
            guard tv.bounds.width > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.restorePosition(tv, y: y)
                }
                return
            }
            tv.layoutManager.ensureLayout(for: tv.textContainer)
            let maxY = max(0, tv.contentSize.height - tv.bounds.height)
            tv.setContentOffset(CGPoint(x: 0, y: min(y, maxY)), animated: false)
            UIView.animate(withDuration: 0.15) { tv.alpha = 1 }
        }
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let coord = context.coordinator
        // 字号/行距变化 → 重建属性串（段落样式随参数变）
        if coord.appliedFontSize != fontSize || coord.appliedLineSpacing != lineSpacing {
            coord.appliedFontSize = fontSize
            coord.appliedLineSpacing = lineSpacing
            uiView.attributedText = makeAttributedText()
        }
        if uiView.backgroundColor != bgColor {
            uiView.backgroundColor = bgColor
        }
        // 初始上报总页数：按屏高估算（连续滚动模式也可知当前大致的页）
        if uiView.bounds.height > 0 {
            let total = max(1, Int(ceil(uiView.contentSize.height / uiView.bounds.height)))
            let cur = max(1, min(total, Int(uiView.contentOffset.y / uiView.bounds.height) + 1))
            coord.onPageChange(cur, total)
        }
        // 目录跳转：目标页对应纯文本偏移滚到顶部
        if let offset = jumpToOffset {
            uiView.layoutManager.ensureLayout(for: uiView.textContainer)
            let clamped = max(0, min(offset, (uiView.text as NSString).length - 1))
            let glyph = uiView.layoutManager.glyphIndexForCharacter(at: clamped)
            let rect = uiView.layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: uiView.textContainer)
            uiView.setContentOffset(CGPoint(x: 0, y: rect.minY - 8), animated: false)
            DispatchQueue.main.async { jumpToOffset = nil }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(book: book, selectionText: $selectionText, selectionContext: $selectionContext)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let book: Book
        @Binding var selectionText: String?
        @Binding var selectionContext: String
        var appliedFontSize: Int = 0
        var appliedLineSpacing: Double = -1
        private var lastY: CGFloat = 0
        var onTap: () -> Void = {}
        var onPageChange: (Int, Int) -> Void = { _, _ in }

        @objc func handleTap() { onTap() }

        init(book: Book, selectionText: Binding<String?>, selectionContext: Binding<String>) {
            self.book = book
            _selectionText = selectionText
            _selectionContext = selectionContext
        }

        // 翻页静止时上报页码
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { reportPage(scrollView) }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { reportPage(scrollView) }
        }
        private func reportPage(_ scrollView: UIScrollView) {
            guard scrollView.isPagingEnabled, scrollView.bounds.height > 0 else { return }
            let current = Int(round(scrollView.contentOffset.y / scrollView.bounds.height)) + 1
            let total = Int(round(scrollView.contentSize.height / scrollView.bounds.height))
            onPageChange(current, max(current, total))
        }

        // 滚动即存阅读位置（节流），并更新书架进度条 + 底部页码
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            guard abs(y - lastY) > 50 else { return }
            lastY = y
            let scrollable = scrollView.contentSize.height - scrollView.bounds.height
            book.scrollOffset = Double(y)
            book.progressFraction = scrollable > 0 ? min(1, max(0, Double(y / scrollable))) : 1
            book.lastReadAt = .now
            try? SelectionCenter.shared.modelContext?.save()
            // 连续滚动也更新页码
            if scrollView.bounds.height > 0 {
                let total = max(1, Int(ceil(scrollView.contentSize.height / scrollView.bounds.height)))
                let cur = max(1, min(total, Int(y / scrollView.bounds.height) + 1))
                onPageChange(cur, total)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange,
                  let text = textView.text(in: range)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                selectionText = nil
                selectionContext = ""
                return
            }
            selectionContext = SelectionContext.around(textView.selectedRange, in: textView.text)
            selectionText = text
        }
    }
}

// MARK: - PDFView 桥接层（文字版 + 图片版统一选字）

private struct _PDFKitBridge: UIViewRepresentable {
    let book: Book
    @Binding var selectionBinding: String?
    @Binding var contextBinding: String
    @Binding var pageBinding: Int
    @Binding var toc: [TOCEntry]
    @Binding var jumpToPage: Int?
    var onTap: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(book: book, selectionBinding: $selectionBinding,
                    contextBinding: $contextBinding, pageBinding: $pageBinding)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground
        if let document = PDFDocument(url: book.fileURL) {
            pdfView.document = document
            if book.progressLocation > 0,
               let page = document.page(at: min(book.progressLocation, document.pageCount - 1)) {
                // PDFView 布局前 go(to:) 不生效，延迟到下一 runloop 再跳；
                // 跳完才允许保存进度，防止被覆盖成第 0 页
                DispatchQueue.main.async {
                    pdfView.go(to: page)
                    if pdfView.currentPage != page {
                        // 布局仍未完成，再试一次
                        DispatchQueue.main.async { pdfView.go(to: page) }
                    }
                    context.coordinator.initialRestoreDone = true
                    context.coordinator.checkCurrentPage()
                }
            } else {
                context.coordinator.initialRestoreDone = true
            }
            // 提取书签目录（outline），回写给目录弹层
            let entries = PDFTOC.extract(from: document)
            DispatchQueue.main.async { toc = entries }
        }
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pdfView)

        // 图片页 OCR 文字层：透明 UITextView 覆盖在 PDF 页面上
        let textLayer = UITextView()
        textLayer.isEditable = false
        textLayer.isSelectable = true
        textLayer.backgroundColor = .clear
        textLayer.textColor = .clear           // 文字不可见，选中才高亮
        textLayer.tintColor = .systemYellow    // 选中高亮色
        textLayer.font = .systemFont(ofSize: 16)
        textLayer.textContainerInset = UIEdgeInsets(top: 24, left: 18, bottom: 24, right: 18)
        textLayer.isHidden = true
        textLayer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textLayer)
        NSLayoutConstraint.activate([
            textLayer.topAnchor.constraint(equalTo: pdfView.topAnchor),
            textLayer.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
            textLayer.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
            textLayer.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor),
        ])

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.pdfView = pdfView
        context.coordinator.textLayer = textLayer
        context.coordinator.observe(pdfView)
        context.coordinator.onTap = onTap
        // 单击：沉浸/恢复（不拦截 PDFView 自身手势）
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        container.addGestureRecognizer(tap)
        context.coordinator.checkCurrentPage()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 目录跳转：跳到目标页后清除请求
        if let target = jumpToPage,
           let page = context.coordinator.pdfView?.document?.page(at: target) {
            context.coordinator.pdfView?.go(to: page)
            DispatchQueue.main.async { jumpToPage = nil }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var selectionBinding: String?
        @Binding var contextBinding: String
        @Binding var pageBinding: Int
        let book: Book

        weak var pdfView: PDFView?
        weak var textLayer: UITextView?
        var onTap: () -> Void = {}
        /// 上次阅读页恢复完成后才允许写进度（防止恢复前被覆盖成第 0 页）
        var initialRestoreDone = false
        private var timer: Timer?
        private var lastText: String?
        private var lastOCRPage: Int = -1

        @objc func handleTap() { onTap() }

        init(book: Book, selectionBinding: Binding<String?>, contextBinding: Binding<String>, pageBinding: Binding<Int>) {
            self.book = book
            _selectionBinding = selectionBinding
            _contextBinding = contextBinding
            _pageBinding = pageBinding
            super.init()
        }

        func observe(_ pdfView: PDFView) {
            // Catalyst 滚轮：递归找到 PDFView 内部所有 scrollView 并开启
            #if targetEnvironment(macCatalyst)
            DispatchQueue.main.async {
                self._fixScrollRecursive(pdfView)
            }
            #endif
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged),
                name: .PDFViewPageChanged, object: pdfView)
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.pollSelection()
            }
            textLayer?.delegate = self
        }

        #if targetEnvironment(macCatalyst)
        private func _fixScrollRecursive(_ view: UIView) {
            if let sv = view as? UIScrollView {
                sv.panGestureRecognizer.allowedScrollTypesMask = .all
            }
            for sub in view.subviews { _fixScrollRecursive(sub) }
        }
        #endif

        @objc func pageChanged() { checkCurrentPage() }

        func checkCurrentPage() {
            guard let pdfView, let page = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let idx = doc.index(for: page)
            Task { @MainActor in
                pageBinding = idx
                guard self.initialRestoreDone else { return }
                // 记录阅读进度（书架进度条 + 下次恢复页码）
                book.progressLocation = idx
                book.progressFraction = doc.pageCount > 1 ? Double(idx) / Double(doc.pageCount - 1) : 1
                book.lastReadAt = .now
                try? SelectionCenter.shared.modelContext?.save()
            }

            if LocalOCR.pageHasText(page) {
                // 文字页：PDFKit 能选字，OCR 层隐藏
                textLayer?.isHidden = true
            } else if idx != lastOCRPage {
                // 图片页且未识别过 → Vision OCR → 文本填入透明覆盖层
                lastOCRPage = idx
                textLayer?.text = ""
                textLayer?.isHidden = false
                let image = pdfView.asImage()
                Task {
                    if let result = try? await LocalOCR.recognize(image),
                       !result.fullText.isEmpty {
                        await MainActor.run {
                            self.textLayer?.text = result.fullText
                            self.textLayer?.textColor = .clear  // 透明文字，选中才显高亮
                        }
                    }
                }
            }
        }

        // 透明文字层 → 检测选中文字 → 传给 SwiftUI 弹工具条
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange,
                  let text = textView.text(in: range)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                if lastText != nil { lastText = nil; selectionBinding = nil; contextBinding = "" }
                return
            }
            if text != lastText {
                lastText = text
                contextBinding = SelectionContext.around(textView.selectedRange, in: textView.text)
                selectionBinding = text
            }
        }

        // PDFKit 文字选段（文字版）
        private func pollSelection() {
            guard textLayer?.isHidden == true,  // 只在文字页用 PDFKit 选段
                  let pdfView, let sel = pdfView.currentSelection,
                  let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                // 文字层已激活或没有 PDFKit 选段 → 不覆盖
                return
            }
            if text != lastText {
                lastText = text
                if let page = sel.pages.first, let doc = pdfView.document {
                    pageBinding = doc.index(for: page)
                    // 取选段所在页前后各 500 字作为上下文
                    if let pageText = page.string {
                        contextBinding = SelectionContext.around(sel.range(at: 0, on: page), in: pageText)
                    }
                }
                selectionBinding = text
            }
        }

        deinit {
            timer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}

extension PDFView {
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { ctx in layer.render(in: ctx.cgContext) }
    }
}
#endif
