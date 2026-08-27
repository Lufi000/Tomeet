import Foundation
import Testing
@testable import Tomeet

struct MockChatServiceTests {
    @Test func replyStreamYieldsNonEmptyReply() async throws {
        let service = MockChatService(chunkDelay: .zero)
        let messages = [ChatMessage(role: .user, text: "这本书讲了什么？")]

        var reply = ""
        for try await chunk in service.replyStream(to: messages, contextBook: nil) {
            reply += chunk
        }

        #expect(!reply.isEmpty)
    }

    @Test func replyStreamMentionsContextBookTitle() async throws {
        let service = MockChatService(chunkDelay: .zero)
        let book = Book(title: "沉思录", author: "Marcus Aurelius", format: .epub)
        let messages = [ChatMessage(role: .user, text: "核心观点是什么？")]

        var reply = ""
        for try await chunk in service.replyStream(to: messages, contextBook: book) {
            reply += chunk
        }

        #expect(reply.contains("沉思录"))
    }
}
