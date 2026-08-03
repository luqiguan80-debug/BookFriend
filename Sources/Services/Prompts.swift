import Foundation

/// 讲解 / 翻译 / 展开 三个核心 prompt（PRD 4.3）
enum Prompts {

    struct Input {
        var action: NoteType
        var bookTitle: String
        var author: String
        var chapterTitle: String
        var selectedText: String
        var context: String   // 选段所在段落的上下文
    }

    static let system = """
        你是一位博学、耐心的伴读助手，正在陪用户读一本书。\
        你的讲解要通俗易懂、直击要点，像一个读过这本书的朋友在聊天，\
        不要堆砌术语，不要复述原文凑字数。用中文回答（翻译功能除外）。
        """

    static func userMessage(_ input: Input) -> String {
        let header = """
            书名：《\(input.bookTitle)》\(input.author.isEmpty ? "" : "，作者：\(input.author)")
            当前章节：\(input.chapterTitle.isEmpty ? "未知" : input.chapterTitle)
            选段所在上下文：
            \"\"\"
            \(input.context)
            \"\"\"
            用户选中的段落：
            \"\"\"
            \(input.selectedText)
            \"\"\"
            """

        let instruction: String
        switch input.action {
        case .explain:
            instruction = """
                请讲解用户选中的这段话。要求：
                1. 先说清楚这段话在讲什么（一两句概括）；
                2. 再解释其中的难点、概念或逻辑；
                3. 如果能联系本书主题或现实例子帮助理解，简要点一句；
                4. 全文 200-400 字，口语化，分自然段。
                """
        case .translate:
            instruction = "请翻译用户选中的段落：如果是外文则译成通顺的中文，如果已是中文则译成英文。只输出译文，不要解释。专业术语要准确。"
        case .expand:
            instruction = """
                请为用户选中的段落展开背景知识，帮助ta读得更明白。可以包括：
                相关概念的通俗解释、涉及的人物/事件/历史背景、这个观点或故事的来龙去脉。
                分点列出，每点一两句话，总共不超过 300 字。
                """
        case .highlight:
            instruction = ""
        }
        return header + "\n" + instruction
    }

    // MARK: - 多轮对话笔记要点提取

    static let summarizeSystem = """
        你是一位阅读笔记整理助手。请从用户与伴读助手围绕书中一段文字的问答对话中，\
        提炼出最值得保留的要点，写成一段条理清晰的中文笔记。要求：\
        1. 合并所有轮次的内容，去重，保留关键解释和结论；\
        2. 不要出现"用户问""助手答"这类对话痕迹，直接输出笔记正文；\
        3. 200-400 字，可分点。
        """

    /// 多轮问答 → 要点提取的 user 消息。selectedText 显式传入，
    /// 避免把首轮 prompt 里冗长的书名/上下文 header 带进总结输入。
    static func summarizeUserMessage(selectedText: String, conversation: [ChatMessage]) -> String {
        var parts = ["""
            书中选段：
            \"\"\"
            \(selectedText)
            \"\"\"
            """]
        var isFirstAnswer = true
        var pendingQuestion: String?
        for message in conversation where !message.isInitialContext && !message.content.isEmpty {
            switch message.role {
            case .user:
                pendingQuestion = message.content
            case .assistant:
                if isFirstAnswer {
                    parts.append("讲解/展开结果：\n\(message.content)")
                    isFirstAnswer = false
                } else {
                    if let q = pendingQuestion { parts.append("追问：\(q)") }
                    parts.append("回答：\n\(message.content)")
                }
                pendingQuestion = nil
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
