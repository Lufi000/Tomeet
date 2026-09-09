import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @State private var selectedBook: Book?       // Book Sheet(Task 6)
    @State private var presentedReader: Book?
    @State private var presentedListen: Book?
    @State private var presentedChat: Book?
    @State private var showImporter = false

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
        .fullScreenCover(item: $presentedReader) { book in
            BookReaderPresenter.view(for: book)
        }
        .fullScreenCover(item: $presentedListen) { book in
            ListenPlayerView(book: book)
        }
        // Task 7 接入:AIAssistantView(book:onBack:) 签名落地后恢复
        // .fullScreenCover(item: $presentedChat) { book in
        //     AIAssistantView(book: book, onBack: { presentedChat = nil })
        // }
        // Book Sheet 在 Task 6 接入:
        // .overlay { if let book = selectedBook { BookSheetView(...) } }
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
