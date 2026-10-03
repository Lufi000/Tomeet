import SwiftUI

/// 对话区(消息流 + 输入条),绑定单本书。BookDetailView 面板与 AIAssistantView 全屏页共用。
/// 视觉按 Manta:用户消息黑色胶囊、AI 回复纯文本无气泡、空态为居中竖排预设问题。
struct BookChatView: View {
    let book: Book

    @State private var viewModel: AIChatViewModel
    @State private var input = ""
    /// 建议问题在 init 算一次,避免每次 body 重算都重读磁盘 JSON。
    @State private var suggestedPrompts: [String]
    @FocusState private var inputFocused: Bool

    init(book: Book) {
        self.book = book
        _viewModel = State(wrappedValue: AIChatViewModel(selectedBook: book))
        _suggestedPrompts = State(wrappedValue: SuggestedPrompts.prompts(for: book))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    promptList
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                if let lastID = viewModel.messages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { inputFocused = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Manta 风格空态:预设问题居中竖排灰字,点击直接发送。
    private var promptList: some View {
        VStack(spacing: 18) {
            ForEach(suggestedPrompts, id: \.self) { prompt in
                Button {
                    Task { await viewModel.send(prompt) }
                } label: {
                    Text(prompt)
                        .font(.book(.subheadline)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about this book...", text: $input, axis: .vertical)
                .font(.book(.body))
                .tracking(Theme.letterSpacing)
                .lineLimit(1...4)
                .focused($inputFocused)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                )
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .tIcon(.subheadline, weight: .bold)
                    .foregroundStyle(canSend ? Color.white : Theme.inkTertiary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(canSend ? Color.black : Theme.inkFaint)
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isResponding
    }

    private func send() {
        let text = input
        // 持焦的 TextField 会完全忽略外部对 binding 的写入(内部缓冲直到失焦才同步),
        // 必须先失焦再清空,随后立即恢复焦点让键盘不收起。
        inputFocused = false
        input = ""
        Task { @MainActor in inputFocused = true }
        Task { await viewModel.send(text) }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            if isThinking {
                // Manta:状态行不套气泡,灰字左对齐
                Text("Thinking")
                    .font(.book(.caption)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkTertiary)
            } else if message.role == .user {
                Text(message.text)
                    .font(.book(.body)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black)
                    )
            } else {
                // Manta:AI 回复纯文本,无气泡
                content
                    .font(.book(.body)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if message.role == .assistant && !isThinking { Spacer(minLength: 48) }
        }
    }

    private var isThinking: Bool {
        message.role == .assistant && message.text.isEmpty
    }

    /// AI 回复按 Markdown 渲染(斜体/粗体/列表),解析失败回退纯文本;
    /// 流式追加时每次重解析,聊天长度下开销可忽略。
    private var content: Text {
        if let attributed = try? AttributedString(markdown: message.text) {
            return Text(attributed)
        }
        return Text(message.text)
    }
}
