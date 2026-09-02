import Foundation
import Testing
@testable import Tomeet

/// 测试用 URL 拦截器。handler 返回 (响应, 响应体)。
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@Suite(.serialized) struct DeepSeekChatServiceTests {
    private func makeService(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> DeepSeekChatService {
        MockURLProtocol.handler = handler
        return DeepSeekChatService(
            appToken: "test-token",
            deviceID: "test-device",
            session: MockURLProtocol.makeSession()
        )
    }

    private func sseResponse(_ request: URLRequest, headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        var allHeaders = ["Content-Type": "text/event-stream"]
        allHeaders.merge(headers) { _, new in new }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: allHeaders
        )!
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\ndata: [DONE]\n\n"
        return (response, Data(body.utf8))
    }

    @Test func sendsDeviceIDHeader() async throws {
        nonisolated(unsafe) var gotDeviceID: String?
        let service = makeService { request in
            gotDeviceID = request.value(forHTTPHeaderField: "X-Device-ID")
            return self.sseResponse(request)
        }
        var text = ""
        for try await chunk in service.replyStream(
            to: [ChatMessage(role: .user, text: "hello")], contextBook: nil
        ) {
            text += chunk
        }
        #expect(gotDeviceID == "test-device")
        #expect(text == "hi")
    }

    @Test func reportsQuotaRemainingFromResponseHeader() async throws {
        final class Capture: @unchecked Sendable { var value: Int? }
        let capture = Capture()
        var service = makeService { request in
            self.sseResponse(request, headers: ["X-Quota-Remaining": "6"])
        }
        service.onQuotaRemaining = { capture.value = $0 }

        for try await _ in service.replyStream(
            to: [ChatMessage(role: .user, text: "hello")], contextBook: nil
        ) {}
        #expect(capture.value == 6)
    }

    @Test func throwsQuotaExceededOn429() async {
        let service = makeService { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil
            )!
            let body = #"{"error":"quota_exceeded","resetAt":"2026-09-03T00:00:00+08:00"}"#
            return (response, Data(body.utf8))
        }
        do {
            for try await _ in service.replyStream(
                to: [ChatMessage(role: .user, text: "hello")], contextBook: nil
            ) {}
            Issue.record("expected quotaExceeded to be thrown")
        } catch ChatServiceError.quotaExceeded(let resetAt) {
            #expect(resetAt != nil)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

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

struct DeviceIDProviderTests {
    @Test func idIsNonEmptyAndStable() {
        #expect(!DeviceIDProvider().id.isEmpty)
        #expect(DeviceIDProvider().id == DeviceIDProvider().id)
    }
}
