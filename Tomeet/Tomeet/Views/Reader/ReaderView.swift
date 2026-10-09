import Combine
import SwiftData
import SwiftUI

/// 全屏阅读器外壳：加载/错误/就绪三分支，支持悬浮菜单、目录与主题设置 Sheet。
struct ReaderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bookClose) private var bookClose
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ReadingTimeTracker.self) private var readingTracker
    @State private var viewModel: ReaderViewModel
    @State private var showMenu = false
    @State private var showChrome = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var showContents = false
    @State private var showThemes = false
    @State private var showListen = false

    init(book: Book) {
        self.book = book
        _viewModel = State(initialValue: ReaderViewModel(book: book))
    }

    var body: some View {
        ZStack {
            themeBackground.ignoresSafeArea()
            content
        }
        .foregroundStyle(themeForeground)
        // 顶栏那个 × 只长在就绪态里（`content` 的 `.ready` 分支才有 `topBar`）。
        // 于是加载一旦卡住或失败，整页就没有任何退出口 —— 人被关在阅读器里出不来。
        // 没就绪时在这里补一个。
        .overlay(alignment: .topLeading) {
            if !viewModel.isReady {
                escapeButton
            }
        }
        .onAppear {
            let settings = ReaderSettings.fetchOrCreate(in: modelContext)
            viewModel.modelContext = modelContext
            viewModel.reloadAnnotations()
            viewModel.apply(settings: settings)
            viewModel.loadBook(pageSize: currentSize, safeAreaInsets: currentSafeAreaInsets)
            readingTracker.begin(.reading)
        }
        .onDisappear {
            readingTracker.end(.reading)
            flushReadingTime()
        }
        .task {
            #if DEBUG
            // 仅供录屏验证：`--ui-snapshot-close` 会在进阅读器几秒后自动按一次 ×。
            // 走的是和手指点**完全同一条路径**（真的 `bookClose` 回调），
            // 不然录到的「合书」就不是用户会看到的那一段。
            guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-close") else { return }
            try? await Task.sleep(for: .seconds(3))
            closeBook(bookClose, orDismiss: dismiss)
            #endif
        }
        .task {
            #if DEBUG
            // 仅供录屏验证：`--ui-snapshot-contents` / `--ui-snapshot-themes`
            // 会在进阅读器后自动展开对应浮层。理由同上面那条 ——
            // 模拟器没有可编程的点击接口，不自己触发就验收不了浮层里的间距。
            let args = ProcessInfo.processInfo.arguments
            let wantsContents = args.contains("--ui-snapshot-contents")
            let wantsThemes = args.contains("--ui-snapshot-themes")
            guard wantsContents || wantsThemes else { return }
            try? await Task.sleep(for: .seconds(2))
            if wantsContents { showContents = true } else { showThemes = true }
            #endif
        }
        .onReceive(readingFlushTimer) { _ in flushReadingTime() }
        .onChange(of: colorScheme) { _, newScheme in
            // 自动夜间开启时系统换外观要跟着换主题
            viewModel.updateAppearance(isDark: newScheme == .dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveCurrentPosition()
                readingTracker.end(.reading)
                flushReadingTime()
            } else if newPhase == .active {
                readingTracker.begin(.reading)
            }
        }
        .sheet(isPresented: $showContents) {
            ContentsSheet(book: book, viewModel: viewModel)
        }
        .sheet(isPresented: $showThemes) {
            ThemesSettingsSheet(settings: viewModel.settings ?? ReaderSettings())
        }
        .fullScreenCover(isPresented: $showListen) {
            ListenPlayerView(book: book)
        }
        .onChange(of: showThemes) { _, isPresented in
            if !isPresented, let settings = viewModel.settings {
                viewModel.apply(settings: settings)
            }
        }
    }

    /// 未就绪时的退出口。与就绪态顶栏那个 × 同一个动作、同一个尺寸，只是位置独立 ——
    /// 它不能依赖 `content` 走到哪个分支。
    private var escapeButton: some View {
        circleButton(icon: "xmark", diameter: chromeControlDiameter) {
            closeBook(bookClose, orDismiss: dismiss)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
    }

    // MARK: - 主题颜色

    /// 用**解析后**的主题：自动夜间开启时会随系统外观切换。
    private var themeBackground: Color {
        viewModel.resolvedTheme.backgroundColor
    }

    private var themeForeground: Color {
        viewModel.resolvedTheme.textColor
    }

    private var chromeColor: Color {
        themeForeground.opacity(0.8)
    }

    // MARK: - 内容分支

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().tint(themeForeground)
        case .failed(let message):
            VStack(spacing: Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .tIcon(IconRole.display)
                    .foregroundStyle(themeForeground.opacity(0.6))
                Text(message)
                    .tText(.secondary, color: themeForeground.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
                Button("Retry") {
                    viewModel.loadBook(pageSize: currentSize, safeAreaInsets: currentSafeAreaInsets)
                }
                .buttonStyle(.borderedProminent)
            }
        case .ready:
            // 卷页要顶到屏幕四边（Apple Books 效果），但正文不能压到灵动岛/Home 指示条。
            // 所以：分页用整屏尺寸，安全区作为额外内衬叠在用户边距之上。
            GeometryReader { proxy in
                let insets = proxy.safeAreaInsets
                let fullSize = CGSize(
                    width: proxy.size.width + insets.leading + insets.trailing,
                    height: proxy.size.height + insets.top + insets.bottom
                )
                ZStack {
                    ReaderHostView(viewModel: viewModel, onToggleChrome: { toggleChrome() })
                        .ignoresSafeArea()

                    if showChrome {
                        // 顶栏与底栏都只在**页边距**里：正文区 [103, 796]（安全区 + 44pt 下限）
                        // 之外，所以怎么翻页都不会有字被压在下面。
                        topBar
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        bottomBar
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        overlayMenu
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }

                    // 用完脚注得能回来。这个按钮**不参与 chrome 自动隐藏** ——
                    // 藏起来用户就找不到回路了（参考 Apple Books 的「↩ 191」）。
                    if viewModel.canReturnFromFootnote {
                        footnoteReturnButton
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showChrome)
                .onAppear {
                    viewModel.relayout(pageSize: fullSize, safeAreaInsets: Self.contentInsets(from: insets))
                    scheduleChromeHide()
                }
                .onChange(of: fullSize) { _, newSize in
                    viewModel.relayout(pageSize: newSize, safeAreaInsets: Self.contentInsets(from: insets))
                }
            }
        }
    }

    /// 章首页的正文里已经排了章标题，顶栏再来一个就会叠字（同一行显示两遍）。
    private var showsChapterTitleInChrome: Bool {
        viewModel.session?.pageMap
            .textPage(globalIndex: viewModel.currentGlobalIndex)?
            .header == nil
    }

    /// 顶栏：**只有一行**，整行落在上边距里。
    ///
    /// 原来是「章节」+ 章名两行，加上 44pt 的关闭键，整体高约 50pt —— 而上边距只有
    /// `ChapterPager.minimumVerticalMargin`（44pt），排不下就压到正文首行上，两行字叠印。
    /// 收成一行 + 收紧控件尺寸，正好装进去。
    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            if showsChapterTitleInChrome {
                Text(currentChapterTitle)
                    .tText(.hint, color: chromeColor)
                    .lineLimit(1)
            }
            Spacer()
            circleButton(icon: "xmark", diameter: chromeControlDiameter) {
                closeBook(bookClose, orDismiss: dismiss)
            }
        }
        .padding(.horizontal, Spacing.md)
        // 上边距 44pt = 34pt 控件 + 上下各留几点的余量（正文区从 103pt 开始）
        .padding(.top, Spacing.xs)
    }

    /// 脚注返回：`↩ 191`（原页码），对齐 Apple Books 的置顶返回条。
    private var footnoteReturnButton: some View {
        Button {
            viewModel.returnFromFootnote()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.uturn.backward")
                    .tIcon(IconRole.control, weight: .semibold)
                Text("\(returnPageNumber)")
                    .tText(.meta, color: themeForeground)
                    .monospacedDigit()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .padding(Spacing.md)
    }

    /// 跳转前的页码（1-based，与底部页码一致）。
    private var returnPageNumber: Int {
        (viewModel.footnoteReturnIndex ?? 0) + 1
    }

    /// 浮层控件的直径。受 `ChapterPager.minimumVerticalMargin` 约束：
    /// 底边距 44pt 要塞下按钮行、上边距 44pt 要塞下章名行 + 关闭键。
    private var chromeControlDiameter: CGFloat { 34 }

    /// Apple Books 风格的原生圆形按钮：半透明圆形底 + SF Symbol。
    private func circleButton(
        icon: String,
        diameter: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .tIcon(IconRole.control, weight: .semibold)
                .foregroundStyle(themeForeground.opacity(0.9))
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(themeForeground.opacity(0.12))
                        .overlay(Circle().stroke(themeForeground.opacity(0.1), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    private var currentChapterTitle: String {
        guard let ref = viewModel.session?.pageMap.pageRef(globalIndex: viewModel.currentGlobalIndex),
              let title = viewModel.session?.document.chapters[safe: ref.chapterIndex]?.title,
              !title.isEmpty else {
            return book.title
        }
        return title
    }

    /// 底栏：操作按钮 + 页码**同一行**，整行落在下边距里。
    ///
    /// 原来是一列浮在正文右下角的圆钮（44pt × 2 + 间距 ≈ 100pt 高），直接压在正文末几行上。
    /// 收到边距里之后就再也碰不到正文了 —— 不给它留边距下限（`ChapterPager.minimumVerticalMargin`）
    /// 的话，用户把边距调小又会压回去。
    private var bottomBar: some View {
        HStack(spacing: Spacing.xs) {
            if book.hasAudio {
                circleButton(icon: "headphones", diameter: chromeControlDiameter) {
                    showListen = true
                    scheduleChromeHide()
                }
            }
            // 书签：已加则实心。点一下切换，不弹面板（对齐 Apple Books）。
            circleButton(
                icon: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                diameter: chromeControlDiameter
            ) {
                viewModel.toggleBookmark()
                scheduleChromeHide()
            }
            circleButton(icon: "list.bullet", diameter: chromeControlDiameter) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMenu.toggle()
                }
                scheduleChromeHide()
            }

            Spacer()

            Text("\(viewModel.currentGlobalIndex + 1) of \(viewModel.totalPages)")
                .tText(.meta, color: themeForeground.opacity(0.5))
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.md)
    }

    private var currentSize: CGSize {
        UIScreen.current?.bounds.size ?? .zero
    }

    /// 首屏分页发生在 GeometryReader 布局之前，从 window scene 取安全区。
    private var currentSafeAreaInsets: ContentInsets {
        ContentInsets(UIWindowScene.currentSafeAreaInsets)
    }

    /// SwiftUI.EdgeInsets → ContentInsets。放在 View 层转换，
    /// 让 ContentInsets 保持不依赖 SwiftUI（它要在后台分页线程上用）。
    private static func contentInsets(from insets: EdgeInsets) -> ContentInsets {
        ContentInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
    }

    // MARK: - 阅读时长统计

    /// 每 10 秒把内存中的时长增量写入 SwiftData；失败则保留待下次重试。
    private let readingFlushTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private func flushReadingTime() {
        let totals = readingTracker.pending
        guard totals != .zero else { return }
        do {
            try DailyReading.add(
                readSeconds: totals.readSeconds,
                listenSeconds: totals.listenSeconds,
                on: Date(),
                to: modelContext
            )
            readingTracker.reset()
        } catch {
            // 写入失败保留 pending，下个周期重试
        }
    }

    // MARK: - 悬浮菜单

    private var readerMenu: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            pillButton(
                title: "Contents · \(Int((book.readingProgress * 100).rounded()))%",
                icon: "list.bullet"
            ) {
                showMenu = false
                showContents = true
            }

            pillButton(title: "Themes & Settings", icon: "textformat") {
                showMenu = false
                showThemes = true
            }
        }
    }

    private func pillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .tText(.button, color: themeForeground)
                Image(systemName: icon)
                    .tIcon(IconRole.control, weight: .semibold)
            }
            .foregroundStyle(themeForeground)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(themeForeground.opacity(0.12), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    /// 弹出的菜单（Contents / Themes 药丸），贴着底栏往上长。
    private var overlayMenu: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Spacer()
            if showMenu {
                readerMenu
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            // 占位：把菜单顶在底栏之上，别盖住底栏那一行。
            Color.clear.frame(height: chromeControlDiameter)
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Chrome visibility

    private func toggleChrome() {
        showChrome.toggle()
        if showChrome {
            scheduleChromeHide()
        } else {
            showMenu = false
            chromeHideTask?.cancel()
        }
    }

    private func scheduleChromeHide() {
        chromeHideTask?.cancel()
        chromeHideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showMenu = false
                showChrome = false
            }
        }
    }
}

// MARK: - Array helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
