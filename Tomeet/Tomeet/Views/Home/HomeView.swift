import SwiftUI
import SwiftData

struct HomeView: View {
    /// 进「库」的入口回调 —— 顶栏那颗 ☰（原来靠底部标签栏）。
    let onOpenLibrary: () -> Void

    @Query private var books: [Book]
    @Environment(BookOpening.self) private var bookOpening
    @State private var presentedListen: Book?
    /// 轮播里各书封面在全局坐标系中的位置，由 `BookCarouselView` 上报。
    @State private var coverFrames: [UUID: CGRect] = [:]
    /// 本次启动是否已经自动续读过 —— 保证一次启动只弹一次，关掉后不再打扰。
    @State private var didAutoResume = false

    private var carouselBooks: [Book] {
        CarouselData.books(books)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            if carouselBooks.isEmpty {
                emptyState
            } else {
                // 点居中的书直接翻开它（原来先弹一个对话详情面板，已去掉）。
                BookCarouselView(books: carouselBooks) { book in
                    openBook(book)
                }
            }

            header
        }
        .onChange(of: books, initial: false) { _, newBooks in
            reconcileStaleSelections(with: newBooks)
        }
        .fullScreenCover(item: $presentedListen) { book in
            ListenPlayerView(book: book)
        }
        .onPreferenceChange(BookCoverFramePreferenceKey.self) { coverFrames = $0 }
        .onAppear {
            openReaderForSnapshotIfRequested()
            resumeReadingIfNeeded()
        }
    }

    /// 启动后直接回到在读的那一页（Apple Books 的行为）。
    ///
    /// 每次启动只自动进一次：`didAutoResume` 挡住二次触发，所以关掉阅读器退回书架后
    /// 不会又被弹进去。没有可续读的书（新用户、全读完）就安静停在书架。
    private func resumeReadingIfNeeded() {
        guard !didAutoResume else { return }
        didAutoResume = true
        guard bookOpening.request == nil else { return }  // 截图钩子已经开了就不抢
        guard let book = ResumeTarget.book(in: books) else { return }
        // 不传原位坐标：冷启动时轮播还没上报封面位置，凭空从屏幕中央长出一张封面
        // 比直接出现更怪。自动续读要的是「立刻回到那一页」，不是看动画。
        bookOpening.open(book, from: nil)
    }

    private func openBook(_ book: Book) {
        bookOpening.open(book, from: coverFrames[book.id])
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
        // 等轮播上报完封面坐标再开，这样录到的是真的「从封面原位翻开」。
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            openBook(first)
        }
        #endif
    }

    /// 全屏页打开期间书可能在 Library tab 被删除,对账清掉指向已删对象的选中态,
    /// 避免后续访问已失效的 SwiftData 对象。
    private func reconcileStaleSelections(with currentBooks: [Book]) {
        let ids = Set(currentBooks.map(\.id))
        bookOpening.closeIfDeleted(existingIDs: ids)
        if let book = presentedListen, !ids.contains(book.id) { presentedListen = nil }
    }

    // MARK: - 固定层

    /// 顶部固定层：大标题在左，头像 + 进「库」的入口在右。不随轮播滚动。
    ///
    /// 只有那颗 ☰ 吃手势：标题与头像各自 `allowsHitTesting(false)`，
    /// 中间那个 `Spacer` 本身没有命中区域 —— 空白处的触摸照旧穿到轮播上。
    /// （原来是整块挂 `allowsHitTesting(false)`，加了按钮就不能那样了。）
    private var header: some View {
        VStack {
            HStack(alignment: .top) {
                Text("I'm\nNow\nReading")
                    .font(.app(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .allowsHitTesting(false)
                Spacer()
                Circle()
                    .fill(LinearGradient(colors: [Theme.sendEnabled, Theme.accent],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                // 进书架的入口。Paper 的做法：顶栏最右一个 ☰，没有底部标签栏。
                Button(action: onOpenLibrary) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(.title3, weight: .medium))
                        .foregroundStyle(Theme.solidInk)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Library")
                .padding(.leading, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
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
                .font(.app(.subheadline))
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
