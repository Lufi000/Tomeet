import SwiftUI
import SwiftData

struct AIAssistantView: View {
    @Query private var books: [Book]
    @State private var viewModel = AIChatViewModel()
    @State private var input = ""
    @State private var showBookPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                messageList
            }
            .background(Color(.systemGray6))
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) { inputBar }
            .sheet(isPresented: $showBookPicker) { bookPicker }
            .onAppear { viewModel.applyDefaultBook(from: books) }
            .onChange(of: books) { _, newBooks in
                viewModel.applyDefaultBook(from: newBooks)
            }
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
                            .foregroundStyle(.secondary)
                        Text(book.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask freely")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Or pick a book to ask about")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12))
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            Text("Meet the mind inside every book")
                .font(.headline)
            Text("Ask a question, dig into a concept,\nor compare what different books say.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(inputPlaceholder, text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.12))
                )
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.blue : Color.gray.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
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
        input = ""
        Task { await viewModel.send(text) }
    }

    // MARK: - Book picker

    private var bookPicker: some View {
        NavigationStack {
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
                            Image(systemName: "checkmark").foregroundStyle(.blue)
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
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose a Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showBookPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.text.isEmpty ? "…" : message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.role == .user ? Color.blue : Color.gray.opacity(0.15))
                )
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }
}
