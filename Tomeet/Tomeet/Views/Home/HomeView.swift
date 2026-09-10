import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @State private var selectedBook: Book?       // Book Sheet(Task 6)
    @State private var presentedReader: Book?
    @State private var presentedListen: Book?
    @State private var presentedChat: Book?
    @State private var showImporter = false
    /// Sheet 关闭后延迟推出全屏页的 pending Task,可取消(见 openAfterSheetDismiss)。
    @State private var pendingOpen: Task<Void, Never>?

    /// 最近在读:有打开记录的按时间倒序(沿用旧 Continue 区取数逻辑)。
    private var recentlyOpened: [Book] {
        books.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            if recentlyOpened.isEmpty {
                emptyState
            } else {
                ReadingGridView(books: recentlyOpened) { book in
                    withAnimation(.spring) { selectedBook = book }
                }
            }

            header
            addBookButton
        }
        .bookImportPresentation(isPresented: $showImporter)
        .onChange(of: books, initial: false) { _, newBooks in
            reconcileStaleSelections(with: newBooks)
        }
        .fullScreenCover(item: $presentedReader) { book in
            BookReaderPresenter.view(for: book)
        }
        .fullScreenCover(item: $presentedListen) { book in
            ListenPlayerView(book: book)
        }
        .fullScreenCover(item: $presentedChat) { book in
            AIAssistantView(book: book, onBack: { presentedChat = nil })
        }
        .overlay {
            if let book = selectedBook {
                BookSheetView(
                    book: book,
                    onClose: { dismissSheet() },
                    onRead: { openAfterSheetDismiss { presentedReader = book } },
                    onListen: { openAfterSheetDismiss { presentedListen = book } },
                    onChat: { openAfterSheetDismiss { presentedChat = book } }
                )
            }
        }
    }

    private func dismissSheet() {
        withAnimation(.spring) { selectedBook = nil }
    }

    /// 先关 Sheet 再全屏推出目标页,避免全屏 cover 叠在磨砂遮罩上造成层级闪烁。
    /// 重复触发时取消上一个 pending Task,防止旧 action 延迟误触。
    private func openAfterSheetDismiss(_ action: @escaping () -> Void) {
        dismissSheet()
        pendingOpen?.cancel()
        pendingOpen = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// Sheet/全屏页打开期间书可能在 Library tab 被删除,对账清掉指向已删对象的选中态,
    /// 避免后续访问已失效的 SwiftData 对象。
    private func reconcileStaleSelections(with currentBooks: [Book]) {
        let ids = Set(currentBooks.map(\.id))
        if let book = selectedBook, !ids.contains(book.id) { selectedBook = nil }
        if let book = presentedReader, !ids.contains(book.id) { presentedReader = nil }
        if let book = presentedListen, !ids.contains(book.id) { presentedListen = nil }
        if let book = presentedChat, !ids.contains(book.id) { presentedChat = nil }
    }

    // MARK: - 固定层

    /// 顶部固定大标题 + 头像,不随网格滚动。
    private var header: some View {
        VStack {
            HStack(alignment: .top) {
                Text("I'm\nNow\nReading")
                    .font(.splendid(.largeTitle, weight: .bold)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Circle()
                    .fill(LinearGradient(colors: [Theme.sendEnabled, Theme.accent],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var addBookButton: some View {
        Button { showImporter = true } label: {
            Text("Add New Book")
                .font(.splendid(.headline, weight: .semibold)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    /// 空态:刺猬插画 + 引导(沿用旧 Continue 空态视觉)。
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("EmptyStateContinue")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 160)
            Text("Books you start reading will appear here.")
                .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
