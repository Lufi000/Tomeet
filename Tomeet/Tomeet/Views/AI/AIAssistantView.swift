import SwiftUI
import SwiftData

struct AIAssistantView: View {
    /// 返回主页（RootView 切换回 Home tab）
    var onBack: () -> Void = {}

    @Query private var books: [Book]
    @State private var viewModel = AIChatViewModel()
    @State private var input = ""
    @State private var showBookPicker = false
    @FocusState private var inputFocused: Bool

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
            .safeAreaInset(edge: .bottom) {
                if viewModel.quota.isExhausted {
                    exhaustedPanel
                } else {
                    inputBar
                }
            }
            .sheet(isPresented: $showBookPicker) { bookPicker }
            .onAppear { viewModel.applyDefaultBook(from: books) }
            .task { await viewModel.quota.refresh() }
            .onChange(of: books) { _, newBooks in
                viewModel.applyDefaultBook(from: newBooks)
            }
        }
    }

    /// tab 根视图没有系统的右滑 pop 手势，手动补一个左边缘右滑返回
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

    private var contextCard: some View {
        Button {
            showBookPicker = true
        } label: {
            HStack(spacing: 12) {
                if let book = viewModel.selectedBook {
                    BookCoverView(book: book).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Asking about")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkTertiary)
                        Text(book.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.title3)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask freely")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Text("Or pick a book to ask about")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.card)
            )
        }
        .buttonStyle(.plain)
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
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Ask a question, dig into a concept,\nor compare what different books say.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let remaining = viewModel.quota.remaining {
                Text(remaining == 1
                     ? "1 free conversation left today"
                     : "\(remaining) free conversations left today")
                    .font(.caption2)
                    .foregroundStyle(remaining <= 3 ? Theme.accent : Theme.inkTertiary)
            }
            HStack(spacing: 10) {
                TextField(inputPlaceholder, text: $input, axis: .vertical)
                    .font(.body)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.canvas)
    }

    private var exhaustedPanel: some View {
        VStack(spacing: 8) {
            Text("That's today's 10 free conversations")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text("Free conversations refresh at midnight.\nUnlimited conversations are coming with subscription.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Theme.canvas)
    }

    private var inputPlaceholder: String {
        if let book = viewModel.selectedBook {
            return "Ask about \"\(book.title)\"..."
        }
        return "Ask anything..."
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

    // MARK: - Book picker

    private var bookPicker: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 系统导航栏标题字体无法定制，标题与 Done 自己画
                HStack {
                    Text("Choose a Book")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Done") { showBookPicker = false }
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                List {
                    Button {
                        viewModel.selectBook(nil)
                        showBookPicker = false
                    } label: {
                        HStack {
                            Label("Ask Freely", systemImage: "bubble.left.and.text.bubble.right")
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.selectedBook == nil {
                                Image(systemName: "checkmark").foregroundStyle(Theme.ink)
                            }
                        }
                    }

                    ForEach(books.sorted(by: Book.sortRecentlyOpened)) { book in
                        Button {
                            viewModel.selectBook(book)
                            showBookPicker = false
                        } label: {
                            HStack(spacing: 12) {
                                BookCoverView(book: book).frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(book.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(book.author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if viewModel.selectedBook?.id == book.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.ink)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            content
                .font(.body)
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
        guard !message.text.isEmpty else { return Text("…") }
        if message.role == .assistant,
           let attributed = try? AttributedString(markdown: message.text) {
            return Text(attributed)
        }
        return Text(message.text)
    }
}
