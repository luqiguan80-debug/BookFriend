#if os(iOS)
import SwiftUI
import SwiftData

struct EPUBReaderView: View {
    let book: Book
    let modelContext: ModelContext

    @State private var viewModel: EPUBViewModel?
    @State private var loadError: String?
    @State private var showTOC = false
    @State private var showFontPanel = false
    @State private var aiRequest: AIRequest?
    @State private var showAnnotation = false
    @AppStorage("reader.theme") private var themeRaw = "light"
    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .light }

    var body: some View {
        HStack(spacing: 0) {
            if showTOC {
                TOCSidebar(entries: (viewModel?.epub.chapters ?? []).indices.map {
                               TOCEntry(title: viewModel?.epub.chapters[$0].title ?? "", level: 0, target: $0)
                           },
                           currentTarget: viewModel?.chapterIndex,
                           onSelect: { viewModel?.goToChapter($0.target) },
                           onClose: { withAnimation { showTOC = false } })
                    .transition(.move(edge: .leading))
                Hairline(true)
            }
            VStack(spacing: 0) {
                if let loadError {
                    ContentUnavailableView("无法打开这本书",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError))
                } else if let viewModel {
                    ZStack(alignment: .bottom) {
                        EPUBWebView(viewModel: viewModel)
                        if viewModel.selection != nil {
                            selectionToolbar(viewModel: viewModel)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(.easeOut(duration: 0.2), value: viewModel.selection != nil)
                        }
                    }
                    chapterNavigationBar(viewModel: viewModel)
                } else {
                    ProgressView("正在解析…")
                }
            }
            .layoutPriority(1)
        }
        .navigationTitle(viewModel?.currentChapter.title ?? "")
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
                Button { showFontPanel.toggle() } label: { Image(systemName: "textformat.size") }
            }
        }
        .sheet(isPresented: $showAnnotation) {
            if let viewModel {
                AnnotationPopover(selectedText: viewModel.selection?.text ?? "",
                    onSave: { note in viewModel.performHighlight(note: note); showAnnotation = false },
                    onCancel: { showAnnotation = false })
            }
        }
        .sheet(item: $aiRequest) { request in
            AIPanelView(request: request)
                .environmentObject(AISettings())
        }
        .task {
            do {
                let epub = try await Task.detached(priority: .userInitiated) {
                    try EPUBParser().parse(
                        epubFile: book.fileURL,
                        extractTo: Storage.extractedDir(for: book.id))
                }.value
                let vm = await MainActor.run {
                    EPUBViewModel(book: book, epub: epub, modelContext: modelContext)
                }
                SelectionCenter.shared.modelContext = modelContext
                self.viewModel = vm
                vm.loadCurrentChapter()
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onDisappear { viewModel?.clearSelection() }
    }

    // MARK: - 悬浮动作条

    private func selectionToolbar(viewModel: EPUBViewModel) -> some View {
        SelectionActionBar(
            onExplain: { dispatchAI(.explain, viewModel) },
            onTranslate: { dispatchAI(.translate, viewModel) },
            onExpand: { dispatchAI(.expand, viewModel) },
            onHighlight: { showAnnotation = true },
            onClose: { viewModel.clearSelection() }
        )
    }

    private func dispatchAI(_ action: NoteType, _ viewModel: EPUBViewModel) {
        if let payload = viewModel.makeAIPayload() {
            viewModel.clearSelection()
            aiRequest = AIRequest(action: action, payload: payload)
        }
    }

    // MARK: - 底部导航

    private func chapterNavigationBar(viewModel: EPUBViewModel) -> some View {
        VStack(spacing: 8) {
            if showFontPanel {
                HStack {
                    Text("A").font(.system(size: 14))
                    Slider(value: Binding(
                        get: { Double(viewModel.fontSize) },
                        set: { viewModel.applyFontSize(Int($0)) }
                    ), in: 13...32, step: 1)
                    Text("A").font(.system(size: 22))
                }
                .padding(.horizontal)
            }
            HStack {
                Button(action: viewModel.prevChapter) {
                    Label("上一章", systemImage: "chevron.left")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                .disabled(viewModel.chapterIndex == 0)
                Spacer()
                Text("\(viewModel.chapterIndex + 1) / \(viewModel.epub.chapters.count)")
                    .font(.system(.footnote, design: .serif)).foregroundStyle(.tertiary)
                Spacer()
                Button(action: viewModel.nextChapter) {
                    Label("下一章", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                .disabled(viewModel.chapterIndex >= viewModel.epub.chapters.count - 1)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(theme.panelBg)
        .overlay(alignment: .top) { Hairline() }
    }
}
#endif
