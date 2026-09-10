import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    private let chatService: any ChatService

    var messages: [ChatMessage] = []
    /// 对话上下文固定为创建时传入的书(详情页「对话」入口,不再支持换书)。
    let selectedBook: Book?
    var isResponding = false

    /// 消息为空才显示预设问题 chips。
    var showsSuggestedPrompts: Bool { messages.isEmpty }

    init(chatService: (any ChatService)? = nil, selectedBook: Book? = nil) {
        // 默认实参在调用点求值(非隔离上下文),DeepSeekChatService() 放这里会触发
        // MainActor 隔离告警;改为可选参数,在 @MainActor 的 init 体内构造默认值。
        self.chatService = chatService ?? DeepSeekChatService()
        self.selectedBook = selectedBook
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

        isResponding = true
        defer { isResponding = false }

        let stream = chatService.replyStream(to: messages, contextBook: selectedBook)
        do {
            for try await chunk in stream {
                guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
                messages[index].text += chunk
            }
        } catch {
            guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            messages[index].text = "Something went wrong. Please check your connection and try again."
        }
    }
}
