import SwiftUI
import SwiftData

struct AIAssistantView: View {
    /// 对话绑定的书(从 Book Sheet 的「对话」按钮进入,上下文固定)。
    let book: Book
    var onBack: () -> Void

    @State private var viewModel: AIChatViewModel
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    init(book: Book, onBack: @escaping () -> Void) {
        self.book = book
        self.onBack = onBack
        _viewModel = State(wrappedValue: AIChatViewModel(selectedBook: book))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                messageList
            }
            .background(Theme.canvas)
            // AI 对话页隐藏整条底部 TabBar，返回主页靠顶部返回按钮/左边缘右滑
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .simultaneousGesture(edgeSwipeBack)
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    /// 全屏页没有系统的右滑 pop 手势，手动补一个左边缘右滑返回
    private var edgeSwipeBack: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard value.startLocation.x < 40,
                      value.translation.width > 60,
                      abs(value.translation.height) < 80 else { return }
                onBack()
            }
    }

    // MARK: - Context card

    /// 静态上下文卡片:封面 + "Asking about" + 书名(上下文固定,不可切换)。
    private var contextCard: some View {
        HStack(spacing: 12) {
            BookCoverView(book: book).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asking about")
                    .font(.splendid(.caption2)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkTertiary)
                Text(book.title)
                    .font(.splendid(.subheadline, weight: .medium)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
        )
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    emptyState
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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Theme.inkSecondary)
            Text("Meet the mind inside every book")
                .font(.splendid(.headline)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.ink)
            Text("Ask a question, dig into a concept,\nor compare what different books say.")
                .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 8) {
            if viewModel.showsSuggestedPrompts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SuggestedPrompts.prompts(for: book), id: \.self) { prompt in
                            Button {
                                Task { await viewModel.send(prompt) }
                            } label: {
                                Text(prompt)
                                    .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Theme.card, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 10) {
                TextField(inputPlaceholder, text: $input, axis: .vertical)
                    .font(.splendid(.body))
                    .tracking(Theme.letterSpacing)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.card)
                    )
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend ? Theme.sendArrow : Theme.inkTertiary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(canSend ? Theme.sendEnabled : Theme.inkFaint)
                        )
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Theme.canvas)
    }

    private var inputPlaceholder: String {
        "Ask about \"\(book.title)\"..."
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isResponding
    }

    private func send() {
        let text = input
        // 持焦的 TextField 会完全忽略外部对 binding 的写入（内部缓冲直到失焦才同步），
        // 必须先失焦再清空，随后立即恢复焦点让键盘不收起。
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
            content
                .font(.splendid(.body)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.role == .user ? Theme.userBubble : Theme.card)
                )
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    /// AI 回复按 Markdown 渲染（斜体/粗体/列表），解析失败回退纯文本；
    /// 流式追加时每次重解析，聊天长度下开销可忽略。
    private var content: Text {
        guard !message.text.isEmpty else {
            return Text(message.role == .assistant ? "Thinking…" : "…")
        }
        if message.role == .assistant,
           let attributed = try? AttributedString(markdown: message.text) {
            return Text(attributed)
        }
        return Text(message.text)
    }
}
