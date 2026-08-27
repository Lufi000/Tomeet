import Foundation

enum ChatServiceError: LocalizedError {
    case http(statusCode: Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .http(let code): return "AI service returned HTTP \(code)."
        case .emptyResponse: return "AI service returned an empty response."
        }
    }
}

/// 经自家 BFF 代理访问 DeepSeek（OpenAI 兼容格式）的流式实现。
/// 流式解析思路复用自 CycleAdvisor 的 LLMService（URLSession.bytes + 逐行 SSE）。
struct DeepSeekChatService: ChatService {
    var model = "deepseek-chat"
    var maxTokens = 1024
    var temperature = 0.7
    var baseURL = URL(string: "https://tomeet-api.smallbeebee.com/v1/chat/completions")!

    private let appToken: String
    private let session: URLSession

    init(appToken: String = Secrets.bffAppToken, session: URLSession = .shared) {
        self.appToken = appToken
        self.session = session
    }

    // MARK: - ChatService

    func replyStream(to messages: [ChatMessage], contextBook: Book?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildURLRequest(messages: messages, contextBook: contextBook)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw ChatServiceError.http(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
                    }
                    for try await line in bytes.lines {
                        guard let data = Self.sseData(from: line),
                              let content = try Self.deltaContent(from: data),
                              !content.isEmpty
                        else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request

    func buildURLRequest(messages: [ChatMessage], contextBook: Book?) throws -> URLRequest {
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": Self.systemPrompt(for: contextBook)]
        ]
        apiMessages += messages.map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func systemPrompt(for book: Book?) -> String {
        let base = "You are Tomeet, an AI reading companion. Reply in the same language the user writes in. Keep answers focused and conversational."
        guard let book else {
            return base + " Help the user with reading, books, and ideas."
        }
        return base + " The user is currently reading \"\(book.title)\" by \(book.author). Answer with this book in mind: unpack its ideas, dig into concepts the user asks about, and connect them to the reader's own situation."
    }

    // MARK: - SSE parsing

    /// 兼容 `data: xxx` 与 `data:xxx` 两种 SSE 行格式，忽略 [DONE]、空行和注释行。
    nonisolated static func sseData(from line: String) -> Data? {
        var payload = line
        if payload.hasPrefix("data: ") {
            payload.removeFirst(6)
        } else if payload.hasPrefix("data:") {
            payload.removeFirst(5)
        } else {
            return nil
        }
        guard payload != "[DONE]" else { return nil }
        return payload.data(using: .utf8)
    }

    /// 从单个 SSE chunk 的 JSON 中提取 delta.content；无内容返回 nil。
    nonisolated static func deltaContent(from data: Data) throws -> String? {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta?
            }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(Chunk.self, from: data).choices.first?.delta?.content
    }
}
