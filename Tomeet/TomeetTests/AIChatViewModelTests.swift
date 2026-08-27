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

    private func makeViewModel(books: [Book] = []) -> AIChatViewModel {
        AIChatViewModel(chatService: MockChatService(chunkDelay: .zero), books: books)
    }

    @Test func sendShowsErrorInAssistantMessageWhenServiceFails() async {
        let viewModel = AIChatViewModel(chatService: FailingChatService(), books: [])

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

    @Test func defaultBookIsMostRecentlyOpened() {
        let older = Book(title: "旧书", author: "A", format: .epub,
                         lastOpenedDate: Date(timeIntervalSinceNow: -3600))
        let newer = Book(title: "新书", author: "B", format: .epub,
                         lastOpenedDate: Date(timeIntervalSinceNow: -60))
        let unopened = Book(title: "未读", author: "C", format: .epub)

        let viewModel = makeViewModel(books: [older, unopened, newer])

        #expect(viewModel.selectedBook?.title == "新书")
    }

    @Test func defaultBookIsNilWhenNothingOpened() {
        let viewModel = makeViewModel(books: [Book(title: "未读", author: "C", format: .epub)])

        #expect(viewModel.selectedBook == nil)
    }

    @Test func applyDefaultBookSelectsMostRecentlyOpened() {
        let newer = Book(title: "新书", author: "B", format: .epub,
                         lastOpenedDate: Date(timeIntervalSinceNow: -60))
        let viewModel = makeViewModel()

        viewModel.applyDefaultBook(from: [newer])

        #expect(viewModel.selectedBook?.title == "新书")
    }

    @Test func applyDefaultBookDoesNotOverrideExistingSelection() {
        let newer = Book(title: "新书", author: "B", format: .epub,
                         lastOpenedDate: Date(timeIntervalSinceNow: -60))
        let chosen = Book(title: "沉思录", author: "Marcus Aurelius", format: .epub)
        let viewModel = makeViewModel()
        viewModel.selectBook(chosen)

        viewModel.applyDefaultBook(from: [newer])

        #expect(viewModel.selectedBook?.title == "沉思录")
    }

    @Test func selectBookChangesContextOfNextReply() async {
        let viewModel = makeViewModel()
        let book = Book(title: "沉思录", author: "Marcus Aurelius", format: .epub)

        viewModel.selectBook(book)
        await viewModel.send("核心观点是什么？")

        #expect(viewModel.selectedBook?.title == "沉思录")
        #expect(viewModel.messages.last?.text.contains("沉思录") == true)
    }

    @Test func selectBookNilClearsContext() async {
        let book = Book(title: "沉思录", author: "Marcus Aurelius", format: .epub)
        let viewModel = makeViewModel(books: [])

        viewModel.selectBook(book)
        viewModel.selectBook(nil)
        await viewModel.send("随便聊聊")

        #expect(viewModel.selectedBook == nil)
        #expect(viewModel.messages.last?.text.contains("沉思录") == false)
    }
}
