import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// 一本书的笔记卡片列表（PRD 4.4），支持导出 Markdown
struct NotesListView: View {
    let book: Book
    @Query private var cards: [NoteCard]
    @State private var activeSheet: ActiveSheet?
    @State private var exportError: String?
    @State private var deletingCard: NoteCard?
    @State private var searchText = ""

    /// 单个 sheet 承载两类内容（同层级多个 .sheet(item:) 会导致 dismiss 失效）
    enum ActiveSheet: Identifiable {
        case export(URL)
        case edit(NoteCard)

        var id: String {
            switch self {
            case .export(let url): return "export-\(url.absoluteString)"
            case .edit(let card): return "edit-\(card.id.uuidString)"
            }
        }
    }

    init(book: Book) {
        self.book = book
        let bookID = book.id
        _cards = Query(filter: #Predicate<NoteCard> { $0.bookID == bookID },
                       sort: [SortDescriptor(\.chapterIndex), SortDescriptor(\.createdAt)])
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView("还没有笔记",
                    systemImage: "note.text",
                    description: Text("阅读时选中文字添加批注或使用 AI 讲解，会自动记到这里"))
            } else {
                List {
                    ForEach(groupedByChapter, id: \.chapter) { group in
                        Section {
                            ForEach(group.cards, content: cardRow)
                            .onDelete { offsets in
                                delete(in: group, at: offsets)
                            }
                        } header: {
                            Text(group.chapter)
                                .font(.system(size: 15, weight: .semibold))
                                .textCase(nil)
                        }
                    }
                }
                .overlay {
                    if filteredCards.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索原文 / 批注 / 章节")
        .navigationTitle("笔记 · \(book.title)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !cards.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { exportMarkdown() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .export(let url):
                ShareSheet(activityItems: [url])
            case .edit(let card):
                NoteEditSheet(card: card, onClose: { activeSheet = nil })
            }
        }
        // macOS 导出不走 sheet（见 exportMarkdown），.export 分支仅 iOS 使用
        .alert("删除这条笔记？", isPresented: .init(
            get: { deletingCard != nil },
            set: { if !$0 { deletingCard = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let card = deletingCard { deleteCard(card) }
                deletingCard = nil
            }
            Button("取消", role: .cancel) { deletingCard = nil }
        } message: {
            Text("删除后不可恢复")
        }
        .alert("导出失败", isPresented: .constant(exportError != nil)) {
            Button("好") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func cardRow(_ card: NoteCard) -> some View {
        NoteCardRow(card: card,
            onEdit: { activeSheet = .edit(card) },
            onDelete: { deletingCard = card })
    }

    /// 模糊过滤：空格分词，每个词都要命中任一字段（原文/批注/章节/书名/类型，忽略大小写）
    private var filteredCards: [NoteCard] {
        let tokens = searchText.split { $0 == " " || $0 == "　" }
        guard !tokens.isEmpty else { return cards }
        return cards.filter { card in
            let haystack = [card.sourceText, card.resultText, card.chapterTitle,
                            card.bookTitle, card.type.displayName]
            return tokens.allSatisfy { token in
                haystack.contains { $0.localizedCaseInsensitiveContains(token) }
            }
        }
    }

    private var groupedByChapter: [(chapter: String, cards: [NoteCard])] {
        var groups: [(String, [NoteCard])] = []
        for card in filteredCards {
            let chapter = card.chapterTitle.isEmpty ? "第 \(card.chapterIndex + 1) 节" : card.chapterTitle
            if let last = groups.last, last.0 == chapter {
                groups[groups.count - 1].1.append(card)
            } else {
                groups.append((chapter, [card]))
            }
        }
        return groups.map { (chapter: $0.0, cards: $0.1) }
    }

    private func delete(in group: (chapter: String, cards: [NoteCard]), at offsets: IndexSet) {
        let context = cards.first?.modelContext
        for index in offsets {
            context?.delete(group.cards[index])
        }
        try? context?.save()
    }

    private func deleteCard(_ card: NoteCard) {
        let context = card.modelContext
        context?.delete(card)
        try? context?.save()
    }

    private func exportMarkdown() {
        do {
            let url = try MarkdownExporter.exportToTempFile(
                bookTitle: book.title, author: book.author, cards: cards)
            #if os(iOS)
            activeSheet = .export(url)
            #else
            // macOS 直接在 Finder 中显示，不弹空 sheet
            NSWorkspace.shared.activateFileViewerSelecting([url])
            #endif
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct NoteCardRow: View {
    let card: NoteCard
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.type.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                Spacer()
                // 图标不大但可点区域给足（iOS 上 15pt 裸图标几乎点不中）
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("编辑")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("删除")
                Text(card.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
            }
            Text(card.sourceText)
                .font(.system(size: 15.5, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
            if !card.resultText.isEmpty {
                // 与侧边栏讲解同一套渲染：Markdown + 衬线 + 宽行距
                MarkdownText(content: card.resultText)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 编辑单条笔记的内容（resultText；sourceText 是书中原文不可改）
/// 关闭通过 onClose 直接置 nil 父级绑定，不依赖 dismiss()（多 sheet 层级下不可靠）
struct NoteEditSheet: View {
    let card: NoteCard
    var onClose: () -> Void
    @State private var text = ""

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // 顶部标题栏：显式关闭按钮
            HStack {
                Text("编辑笔记").font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            editContent
            Divider()
            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button("保存", action: save).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .onAppear { text = card.resultText }
        .onExitCommand(perform: onClose)
        .frame(minWidth: 420, minHeight: 320)
        #else
        NavigationStack {
            editContent
                .navigationTitle("编辑笔记")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                    ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
                }
        }
        .onAppear { text = card.resultText }
        .presentationDetents([.medium, .large])
        #endif
    }

    private var editContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.sourceText)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            TextEditor(text: $text)
                .font(.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
    }

    private func save() {
        card.resultText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try? card.modelContext?.save()
        onClose()
    }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
/// macOS 导出不走 sheet（exportMarkdown 直接调 NSWorkspace），此分支不会呈现
struct ShareSheet: View {
    let activityItems: [Any]
    var body: some View { EmptyView() }
}
#endif
