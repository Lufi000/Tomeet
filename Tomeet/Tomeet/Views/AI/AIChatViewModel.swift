import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    private let chatService: any ChatService

    var messages: [ChatMessage] = []
    var selectedBook: Book?
    var isResponding = false

    init(chatService: (any ChatService)? = nil, books: [Book] = []) {
        // 默认实参在调用点求值（非隔离上下文），DeepSeekChatService() 放这里会触发
        // MainActor 隔离告警；改为可选参数，在 @MainActor 的 init 体内构造默认值。
        self.chatService = chatService ?? DeepSeekChatService()
        // 默认选中最近在读的书（§AI Tab 设计：进入后自动带上当前阅读上下文）
        self.selectedBook = Self.mostRecentlyOpened(in: books)
    }

    /// 视图侧 @Query 数据就绪后补选默认书；已手动选择过则不覆盖。
    func applyDefaultBook(from books: [Book]) {
        guard selectedBook == nil else { return }
        selectedBook = Self.mostRecentlyOpened(in: books)
    }

    private static func mostRecentlyOpened(in books: [Book]) -> Book? {
        books.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
            .first
    }

    func selectBook(_ book: Book?) {
        selectedBook = book
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
