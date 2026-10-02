import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @State private var selectedBook: Book?       // 详情面板
    @State private var presentedReader: Book?
    @State private var presentedListen: Book?
    @State private var showImporter = false
    /// 面板关闭后延迟推出全屏页的 pending Task,可取消(见 openAfterSheetDismiss)。
    @State private var pendingOpen: Task<Void, Never>?

    private var carouselBooks: [Book] {
        CarouselData.books(books)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.homeCanvas.ignoresSafeArea()

            if carouselBooks.isEmpty {
                emptyState
            } else {
                BookCarouselView(books: carouselBooks) { book in
                    withAnimation(.spring) { selectedBook = book }
                }
            }

            header
            addBookButton
        }
        .bookImportPresentation(isPresented: $showImporter)
        .toolbar(selectedBook == nil ? .visible : .hidden, for: .tabBar)
        .onChange(of: books, initial: false) { _, newBooks in
            reconcileStaleSelections(with: newBooks)
        }
        .fullScreenCover(item: $presentedReader) { book in
            BookReaderPresenter.view(for: book)
        }
        .fullScreenCover(item: $presentedListen) { book in
            ListenPlayerView(book: book)
        }
        .overlay {
            if let book = selectedBook {
                BookDetailView(
                    book: book,
                    onClose: { dismissPanel() },
                    onRead: { openAfterPanelDismiss { presentedReader = book } },
                    onListen: { openAfterPanelDismiss { presentedListen = book } }
                )
            }
        }
        .onAppear { openReaderForSnapshotIfRequested() }
    }

    /// 仅供截图验证：`xcrun simctl launch <udid> com.ivy.Tomeet --ui-snapshot-reader`
    /// 会直接打开轮播第一本书的阅读器。
    ///
    /// 模拟器没有可编程的点击接口，没有这个口子就没法给阅读器截图 ——
    /// 而卷页是否顶到屏幕边缘这种事，纯逻辑测试证明不了，必须用眼睛看。
    private func openReaderForSnapshotIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-reader"),
              let first = carouselBooks.first else { return }
        presentedReader = first
        #endif
    }

    private func dismissPanel() {
        withAnimation(.spring) { selectedBook = nil }
    }

    /// 先收面板再全屏推出目标页,避免全屏 cover 叠在磨砂面板上造成层级闪烁。
    /// 重复触发时取消上一个 pending Task,防止旧 action 延迟误触。
    private func openAfterPanelDismiss(_ action: @escaping () -> Void) {
        dismissPanel()
        pendingOpen?.cancel()
        pendingOpen = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// 面板/全屏页打开期间书可能在 Library tab 被删除,对账清掉指向已删对象的选中态,
    /// 避免后续访问已失效的 SwiftData 对象。
    private func reconcileStaleSelections(with currentBooks: [Book]) {
        let ids = Set(currentBooks.map(\.id))
        if let book = selectedBook, !ids.contains(book.id) { selectedBook = nil }
        if let book = presentedReader, !ids.contains(book.id) { presentedReader = nil }
        if let book = presentedListen, !ids.contains(book.id) { presentedListen = nil }
    }

    // MARK: - 固定层

    /// 顶部固定大标题 + 头像,不随轮播滚动。
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
        .opacity(selectedBook == nil ? 1 : 0)
    }

    /// 空态:刺猬插画 + 引导。
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
