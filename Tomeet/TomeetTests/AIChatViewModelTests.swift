import Foundation
import Testing
@testable import Tomeet

@MainActor
struct AIChatViewModelTests {
    private struct FailingChatService: ChatService {
        func replyStream(to messages: [ChatMessage], contextBook: Book?) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish(throwing: URLError(.notConnectedToInternet)) }
        }
    }

    private func makeViewModel(book: Book? = nil) -> AIChatViewModel {
        AIChatViewModel(chatService: MockChatService(chunkDelay: .zero), selectedBook: book)
    }

    @Test func sendShowsErrorInAssistantMessageWhenServiceFails() async {
        let viewModel = AIChatViewModel(chatService: FailingChatService())

        await viewModel.send("你好")

        #expect(viewModel.messages.last?.role == .assistant)
        #expect(viewModel.messages.last?.text.isEmpty == false)
        #expect(!viewModel.isResponding)
    }

    @Test func sendAppendsUserMessageAndAssistantReply() async {
        let viewModel = makeViewModel()

        await viewModel.send("你好")

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[0].text == "你好")
        #expect(viewModel.messages[1].role == .assistant)
        #expect(!viewModel.messages[1].text.isEmpty)
    }

    @Test func sendIgnoresBlankText() async {
        let viewModel = makeViewModel()

        await viewModel.send("   ")

        #expect(viewModel.messages.isEmpty)
    }

    @Test func sendEndsWithNotResponding() async {
        let viewModel = makeViewModel()

        await viewModel.send("你好")

        #expect(!viewModel.isResponding)
    }

    @Test func selectedBookComesFromInitializer() async {
        let book = Book(title: "沉思录", author: "Marcus Aurelius", format: .epub)
        let viewModel = makeViewModel(book: book)

        await viewModel.send("核心观点是什么？")

        #expect(viewModel.selectedBook?.title == "沉思录")
        #expect(viewModel.messages.last?.text.contains("沉思录") == true)
    }

    @Test func suggestedPromptsHideAfterFirstMessage() async {
        let viewModel = makeViewModel()
        #expect(viewModel.showsSuggestedPrompts)

        await viewModel.send("你好")

        #expect(!viewModel.showsSuggestedPrompts)
    }
}
