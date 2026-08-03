import Foundation

/// 划线讲解/展开会话中的一条消息（会话级，不持久化；最终只落 NoteCard）
struct ChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user, assistant
    }

    let id = UUID()
    var role: Role
    var content: String
    /// 首条 user 消息含书名/上下文/选段等完整 Prompts header，
    /// 每轮都发给大模型，但不在聊天气泡里渲染（面板顶部已有选段引用框）
    var isInitialContext = false
}
