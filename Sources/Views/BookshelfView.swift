import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ReaderView: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let _ = NSLog("[ShuYou] ReaderView body: \(book.title)")
        #if os(macOS)
        switch book.format {
        case .epub: MacEPUBReaderView(book: book, modelContext: modelContext)
        case .pdf:  MacPDFReaderView(book: book)
        case .txt:  MacTXTReaderView(book: book)
        }
        #else
        switch book.format {
        case .epub: EPUBReaderView(book: book, modelContext: modelContext)
        case .pdf:  PDFReaderView(book: book)
        case .txt:  TXTReaderView(book: book)
        }
        #endif
    }
}

struct BookshelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadAt, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var importError: String?
    @State private var showSettings = false
    @State private var importingBooks: [ImportTask] = []

    struct ImportTask: Identifiable {
        let id = UUID()
        let name: String
    }

    #if os(macOS)
    @State private var notesBook: Book?
    #else
    @State private var selectedBook: Book?
    @State private var notesBook: Book?
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 20, alignment: .top)]
    #endif

    var body: some View {
        NavigationStack {
            Group {
                // 有导入中的占位卡片时也要显示网格，否则空书架导入毫无反馈
                if books.isEmpty && importingBooks.isEmpty {
                    emptyState
                } else {
                    #if os(macOS)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 28, alignment: .top)], spacing: 28) {
                            ForEach(importingBooks) { task in
                                VStack(alignment: .leading, spacing: 8) {
                                    Color.clear
                                        .aspectRatio(0.72, contentMode: .fit)
                                        .overlay {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color(red: 0.96, green: 0.945, blue: 0.92))
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                                VStack(spacing: 8) {
                                                    ProgressView()
                                                        .controlSize(.large)
                                                    Text("导入中…")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    Text(task.name)
                                        .font(.system(size: 13, design: .serif))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                                }
                            }
                            ForEach(books) { book in
                                NavigationLink(destination: ReaderView(book: book)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Color.clear
                                            .aspectRatio(0.72, contentMode: .fit)
                                            .overlay { BookCoverView(book: book) }
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                                            .allowsHitTesting(false)
                                        Text(book.title)
                                            .font(.system(size: 13, design: .serif))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                                            .allowsHitTesting(false)
                                        ProgressLine(fraction: book.progressFraction)
                                            .allowsHitTesting(false)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("查看笔记") { notesBook = book }
                                    Button("删除", role: .destructive) { delete(book) }
                                }
                            }
                        }
                        .padding(24)
                    }
                    .navigationDestination(item: $notesBook) { book in NotesListView(book: book) }
                    #else
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(importingBooks) { task in
                                VStack(spacing: 8) {
                                    Color.clear
                                        .aspectRatio(0.72, contentMode: .fit)
                                        .overlay {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color(.secondarySystemBackground))
                                                VStack(spacing: 8) {
                                                    ProgressView()
                                                    Text("导入中…").font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    Text(task.name).font(.caption).lineLimit(2)
                                }
                            }
                            ForEach(books) { book in
                                BookCell(book: book)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedBook = book }
                                    .contextMenu {
                                        Button("查看笔记") { notesBook = book }
                                        Button("删除", role: .destructive) { delete(book) }
                                    }
                            }
                        }
                        .padding()
                    }
                    #endif
                }
            }
            .navigationTitle("书架")
            #if !os(macOS)
            .navigationDestination(item: $selectedBook) { book in ReaderView(book: book) }
            .navigationDestination(item: $notesBook) { book in NotesListView(book: book) }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: Self.importableTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            #if os(macOS)
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
            #else
            .sheet(isPresented: $showSettings) { SettingsView() }
            #endif
            .alert("导入失败", isPresented: .constant(importError != nil)) {
                Button("好") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .onAppear {
            SelectionCenter.shared.modelContext = modelContext
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("书架是空的", systemImage: "books.vertical")
        } actions: {
            Button("导入书籍") { showImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // 只让 EPUB/PDF/TXT 可选，其余格式在文件面板里直接置灰
    // epub UTI 由 Info.plist 的 UTImportedTypeDeclarations 声明；txt 用扩展名动态类型，避免 .plainText 把 md/csv 等也放进来
    static let importableTypes: [UTType] = [
        UTType(importedAs: "org.idpf.epub"),
        .pdf,
        UTType(filenameExtension: "txt", conformingTo: .plainText) ?? .plainText,
    ]

    private func handleImport(_ result: Result<[URL], Error>) {
        // 文件选择器本身的错误也要报出来，不能静默吞掉
        let url: URL
        do {
            guard let picked = try result.get().first else { return }
            url = picked
        } catch {
            importError = error.localizedDescription
            return
        }
        NSLog("[BookFriend] 开始导入: \(url.lastPathComponent)")
        let task = ImportTask(name: url.deletingPathExtension().lastPathComponent)
        importingBooks.append(task)
        Task {
            do {
                _ = try await BookImporter.importBook(from: url, into: modelContext)
                NSLog("[BookFriend] 导入完成: \(url.lastPathComponent)")
                importingBooks.removeAll { $0.id == task.id }
            } catch {
                NSLog("[BookFriend] 导入失败: \(error.localizedDescription)")
                importingBooks.removeAll { $0.id == task.id }
                importError = error.localizedDescription
            }
        }
    }

    private func delete(_ book: Book) {
        book.deleteFiles()
        modelContext.delete(book)
        try? modelContext.save()
    }
}

#if os(macOS)
struct BookRow: View {
    let book: Book
    var body: some View {
        let _ = NSLog("[ShuYou] BookRow body: \(book.title)")
        HStack(spacing: 14) {
            BookCoverView(book: book).frame(width: 56, height: 80).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.body).lineLimit(1).textSelection(.enabled)
                if !book.author.isEmpty { Text(book.author).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                ProgressView(value: book.progressFraction).tint(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
#endif

struct BookCell: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(0.72, contentMode: .fit)
                .overlay { BookCoverView(book: book) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            Text(book.title)
                .font(titleFont)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: titleHeight, alignment: .topLeading)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            ProgressLine(fraction: book.progressFraction)
        }
    }

    #if targetEnvironment(macCatalyst)
    private let titleFont: Font = .system(.body, design: .serif)
    private let titleHeight: CGFloat = 42
    #else
    private let titleFont: Font = .system(size: 12, design: .serif)
    private let titleHeight: CGFloat = 30
    #endif
}
