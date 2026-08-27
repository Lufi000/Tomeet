import Foundation
import Testing
@testable import Tomeet

struct DeepSeekChatServiceTests {
    // MARK: - SSE line parsing

    @Test func sseDataParsesStandardLine() {
        let line = #"data: {"choices":[{"delta":{"content":"你"}}]}"#
        let data = DeepSeekChatService.sseData(from: line)
        #expect(data != nil)
        #expect(String(data: data!, encoding: .utf8)!.contains("你"))
    }

    @Test func sseDataParsesCompactLineWithoutSpace() {
        let line = #"data:{"choices":[]}"#
        #expect(DeepSeekChatService.sseData(from: line) != nil)
    }

    @Test func sseDataIgnoresDoneMarker() {
        #expect(DeepSeekChatService.sseData(from: "data: [DONE]") == nil)
    }

    @Test func sseDataIgnoresEmptyAndCommentLines() {
        #expect(DeepSeekChatService.sseData(from: "") == nil)
        #expect(DeepSeekChatService.sseData(from: ": keep-alive") == nil)
    }

    // MARK: - Delta extraction

    @Test func deltaContentExtractsText() throws {
        let json = #"{"choices":[{"delta":{"content":"hello"}}]}"#
        let content = try DeepSeekChatService.deltaContent(from: Data(json.utf8))
        #expect(content == "hello")
    }

    @Test func deltaContentReturnsNilWhenNoContent() throws {
        let json = #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        let content = try DeepSeekChatService.deltaContent(from: Data(json.utf8))
        #expect(content == nil)
    }

    // MARK: - System prompt

    @Test func systemPromptMentionsBookTitleAndAuthor() {
        let book = Book(title: "Meditations", author: "Marcus Aurelius", format: .epub)
        let prompt = DeepSeekChatService.systemPrompt(for: book)
        #expect(prompt.contains("Meditations"))
        #expect(prompt.contains("Marcus Aurelius"))
    }

    @Test func systemPromptWithoutBookIsGeneral() {
        let prompt = DeepSeekChatService.systemPrompt(for: nil)
        #expect(!prompt.isEmpty)
    }

    // MARK: - Request building

    @Test func buildRequestBodyUsesAppTokenHeaderAndStream() throws {
        let service = DeepSeekChatService(appToken: "test-token")
        let messages = [ChatMessage(role: .user, text: "hi")]
        let request = try service.buildURLRequest(messages: messages, contextBook: nil)

        #expect(request.value(forHTTPHeaderField: "X-App-Token") == "test-token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.absoluteString == "https://tomeet-api.smallbeebee.com/v1/chat/completions")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        #expect(body?["stream"] as? Bool == true)
        #expect(body?["model"] as? String == "deepseek-chat")
        let apiMessages = body?["messages"] as? [[String: String]]
        #expect(apiMessages?.first?["role"] == "system")
        #expect(apiMessages?.last?["role"] == "user")
        #expect(apiMessages?.last?["content"] == "hi")
    }
}
