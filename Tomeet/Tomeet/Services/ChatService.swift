import Foundation

/// AI 对话后端抽象。接入真实模型时新增一个实现替换 Mock 即可，UI 层不变。
protocol ChatService: Sendable {
    /// 流式返回 AI 回复片段；失败时抛错（网络错误、鉴权失败等）。
    /// contextBook 为当前对话针对的书，nil 表示自由提问。
    func replyStream(to messages: [ChatMessage], contextBook: Book?) -> AsyncThrowingStream<String, Error>
}

/// 原型占位实现：返回固定文案的流式回复，提示模型将在下个版本接入。
struct MockChatService: ChatService {
    var chunkDelay: Duration = .milliseconds(20)

    func replyStream(to messages: [ChatMessage], contextBook: Book?) -> AsyncThrowingStream<String, Error> {
        let reply: String
        if let book = contextBook {
            reply = "The AI model arrives next version. Then I'll answer based on \"\(book.title)\" — unpacking ideas, digging into concepts, and connecting them to your situation."
        } else {
            reply = "The AI model arrives next version. Then you can ask me anything, or pick a book and I'll answer with it in mind."
        }
        let delay = chunkDelay
        return AsyncThrowingStream { continuation in
            Task {
                for character in reply {
                    if delay > .zero {
                        try? await Task.sleep(for: delay)
                    }
                    continuation.yield(String(character))
                }
                continuation.finish()
            }
        }
    }
}
