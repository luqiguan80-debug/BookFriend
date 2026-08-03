import SwiftUI
import SwiftData

struct AIPanelView: View {
    let request: AIRequest
    var onClose: (() -> Void)?
    @EnvironmentObject var settings: AISettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var isStreaming = true
    @State private var savedCard: NoteCard?
    @State private var roundTask: Task<Void, Never>?
    @State private var started = false
    @State private var stoppedByUser = false
    @AppStorage("reader.theme") private var themeRaw = "light"
    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .light }
    @Query private var allBooks: [Book]
    private var payloadBook: Book? { allBooks.first { $0.id == request.payload.bookID } }

    private var supportsFollowUp: Bool { request.action == .explain || request.action == .expand }
    private var roundCount: Int { messages.filter { $0.role == .assistant && !$0.content.isEmpty }.count }
    private var lastAssistantContent: String { messages.last { $0.role == .assistant }?.content ?? "" }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(request.action.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    saveIndicator
                    // macOS 侧边栏：必须走 onClose 关闭；dismiss() 会把整个阅读器 pop 出导航栈
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Hairline()
                contentBody
            }
            // 整块侧边栏（含头部）跟随阅读主题变色；瞬时切换，和阅读页同步。
            // 只允许水平/底部溢出到窗口边缘，顶部收在安全区内，不染标题栏
            .background(theme.panelBg, ignoresSafeAreaEdges: [.horizontal, .bottom])
            #else
            NavigationStack {
                contentBody
                    .background(theme.panelBg, ignoresSafeAreaEdges: [.horizontal, .bottom])
                    .navigationTitle(request.action.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                        ToolbarItem(placement: .topBarTrailing) { saveIndicator }
                    }
            }
            .presentationDetents([.medium, .large])
            #endif
        }
        .onAppear {
            guard !started else { return }
            started = true
            roundTask = Task { await runInitialRound() }
        }
        .onDisappear {
            roundTask?.cancel()
            summarizeOnClose()
        }
        .animation(nil, value: themeRaw)
    }

    @ViewBuilder
    private var saveIndicator: some View {
        if savedCard != nil {
            #if os(macOS)
            Label(roundCount >= 2 ? "已存（含 \(roundCount) 轮要点）" : "已存",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.iconOnly)
                .help(roundCount >= 2 ? "已存（含 \(roundCount) 轮要点）" : "已存")
            #else
            // 对号 = 已存状态；可点，直接跳这本书的笔记页查看
            let savedLabel = Label(roundCount >= 2 ? "已存（含 \(roundCount) 轮要点）" : "已存",
                  systemImage: "checkmark.circle.fill")
            if let book = payloadBook {
                NavigationLink(destination: NotesListView(book: book)) {
                    savedLabel.foregroundStyle(.green)
                }
            } else {
                savedLabel.foregroundStyle(.green)
            }
            #endif
        } else if !lastAssistantContent.isEmpty, !isStreaming {
            Button { Task { await persistNote(manual: true) } } label: {
                #if os(macOS)
                Image(systemName: "square.and.arrow.down")
                #else
                Label("存笔记", systemImage: "square.and.arrow.down")
                #endif
            }
            .help("存笔记")
        }
    }

    private var contentBody: some View {
        VStack(spacing: 0) {
            // 选段原文钉在顶部，不随对话滚动（超长时自身可滚动）
            ScrollView { quoteBlock }
                .frame(maxHeight: 130)
                .padding(.horizontal, 20).padding(.vertical, 12)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(messages) { message in
                        if !message.isInitialContext {
                            bubble(for: message)
                        }
                    }

                    if isStreaming {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(lastAssistantContent.isEmpty ? "思考中…" : "生成中…")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            // 支持追问的面板：停止按钮固定在底部输入栏发送键旁，不随内容滚动
                            if !supportsFollowUp {
                                Button("停止") { stopGeneration() }
                                    .font(.caption).foregroundStyle(.secondary)
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .defaultScrollAnchor(.bottom)

            if supportsFollowUp {
                Hairline()
                followUpBar
            }
        }
    }

    /// 选段引文：细竖条 + 衬线小字 + 出处，书页边注式的安静呈现
    private var quoteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1.5)
                Text(request.payload.text)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !request.payload.chapterTitle.isEmpty {
                Text(request.payload.chapterTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12)
            }
        }
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            // 用户追问：低存在感的中性灰泡，不抢正文
            Text(message.content)
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        case .assistant:
            // AI 正文：Markdown + 衬线大字 + 宽行距（与笔记列表同一套渲染）
            MarkdownText(content: message.content.isEmpty ? "…" : message.content)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var followUpBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("继续追问…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                .onSubmit { sendFollowUp() }
            // 流式中：发送键旁固定一个停止键，随时可点，不用滚回内容区找
            if isStreaming {
                Button { stopGeneration() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.background)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .help("停止生成")
            }
            Button { sendFollowUp() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.background)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(canSend && !isStreaming
                        ? Color.primary.opacity(0.85) : Color.primary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .disabled(isStreaming || !canSend)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - 对话轮次

    private func runInitialRound() async {
        let input = Prompts.Input(action: request.action, bookTitle: request.payload.bookTitle,
            author: request.payload.author, chapterTitle: request.payload.chapterTitle,
            selectedText: request.payload.text, context: request.payload.context)
        // 首轮消息永久留在 messages 里，后续每轮请求都带全量历史
        messages.append(ChatMessage(role: .user, content: Prompts.userMessage(input), isInitialContext: true))
        await streamCurrentRound()
    }

    private func sendFollowUp() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming, supportsFollowUp else { return }
        error = nil
        draft = ""
        messages.append(ChatMessage(role: .user, content: question))
        isStreaming = true
        roundTask = Task { await streamCurrentRound() }
    }

    private func stopGeneration() {
        stoppedByUser = true
        roundTask?.cancel()
    }

    /// 上送大模型的历史：过滤空占位，并合并连续同角色消息（如首轮被停止后直接追问），
    /// 保证 user 开头、角色交替（Anthropic 硬性要求）
    private func wireHistory() -> [ChatMessage] {
        var result: [ChatMessage] = []
        for message in messages where !message.content.isEmpty {
            if let last = result.last, last.role == message.role {
                result[result.count - 1].content += "\n\n" + message.content
            } else {
                result.append(message)
            }
        }
        return result
    }

    private func streamCurrentRound() async {
        stoppedByUser = false
        messages.append(ChatMessage(role: .assistant, content: ""))
        let lastIdx = messages.count - 1
        let service = AIService()
        do {
            for try await chunk in service.stream(system: Prompts.system, messages: wireHistory(), settings: settings) {
                messages[lastIdx].content += chunk
            }
            isStreaming = false
            await persistNote()
        } catch {
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            let partial = messages[lastIdx].content
            if partial.isEmpty {
                messages.remove(at: lastIdx)
                // 追问轮：把问题撤回输入框，避免下轮出现连续两条 user 消息（Anthropic 不允许）
                if lastIdx - 1 >= 0, !messages[lastIdx - 1].isInitialContext, messages[lastIdx - 1].role == .user {
                    draft = messages[lastIdx - 1].content
                    messages.remove(at: lastIdx - 1)
                }
            }
            isStreaming = false
            if cancelled {
                // 用户主动停止：保留已生成的部分内容并存笔记；面板关闭触发的取消则直接丢弃
                if stoppedByUser, !partial.isEmpty { await persistNote() }
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - 笔记保存

    private func persistNote(manual: Bool = false) async {
        guard !lastAssistantContent.isEmpty else { return }
        if savedCard == nil {
            guard manual || settings.autoSaveCards else { return }
            let card = NoteCard(bookID: request.payload.bookID, bookTitle: request.payload.bookTitle,
                chapterIndex: request.payload.chapterIndex, chapterTitle: request.payload.chapterTitle,
                type: request.action, sourceText: request.payload.text, contextText: request.payload.context,
                resultText: lastAssistantContent, offsetInChapter: request.payload.offset)
            modelContext.insert(card)
            try? modelContext.save()
            savedCard = card
            return
        }
        // 多轮对话：每轮结束先存问答转录（本地零成本，防中途被杀丢内容）；
        // 大模型要点提炼留到面板关闭时只做一次（原来每轮都调，成本翻倍）
        guard roundCount >= 2 else { return }
        savedCard?.resultText = transcriptFallback()
        try? modelContext.save()
    }

    /// 面板关闭时做一次要点提炼；失败则保留转录，不丢内容
    private func summarizeOnClose() {
        guard let card = savedCard, roundCount >= 2 else { return }
        let conversation = messages
        let selectedText = request.payload.text
        let settings = self.settings
        let context = modelContext
        Task { @MainActor in
            if let summary = try? await AIService().complete(system: Prompts.summarizeSystem,
                    user: Prompts.summarizeUserMessage(selectedText: selectedText, conversation: conversation),
                    settings: settings),
               !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                card.resultText = summary
                try? context.save()
            }
        }
    }

    /// 要点提取失败时的兜底：完整问答转录，不丢内容
    private func transcriptFallback() -> String {
        var parts: [String] = []
        var pendingQuestion: String?
        for message in messages where !message.isInitialContext && !message.content.isEmpty {
            switch message.role {
            case .user:
                pendingQuestion = message.content
            case .assistant:
                if parts.isEmpty, pendingQuestion == nil {
                    parts.append(message.content)
                } else {
                    if let q = pendingQuestion { parts.append("问：\(q)") }
                    parts.append("答：\(message.content)")
                }
                pendingQuestion = nil
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
