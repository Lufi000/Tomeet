import Combine
import SwiftData
import SwiftUI

/// 全屏阅读器外壳：加载/错误/就绪三分支，支持悬浮菜单、目录与主题设置 Sheet。
struct ReaderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
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
            VStack(spacing: Spacing.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .tIcon(IconRole.display)
                    .foregroundStyle(themeForeground.opacity(0.6))
                Text(message)
                    .tText(.secondary, color: themeForeground.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
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
                        topBar
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        bottomBar
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        overlayButtons
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(sectionLabel)
                    .tText(.hint, color: chromeColor.opacity(0.7))
                    .lineLimit(1)
                Text(currentChapterTitle)
                    .tText(.secondary, color: themeForeground)
                    .lineLimit(1)
            }
            Spacer()
            circleButton(icon: "xmark") {
                dismiss()
            }
        }
        .padding()
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
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .padding(Spacing.lg)
    }

    /// 跳转前的页码（1-based，与底部页码一致）。
    private var returnPageNumber: Int {
        (viewModel.footnoteReturnIndex ?? 0) + 1
    }

    /// Apple Books 风格的原生圆形按钮：半透明圆形底 + SF Symbol。
    private func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .tIcon(IconRole.control, weight: .semibold)
                .foregroundStyle(themeForeground.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(themeForeground.opacity(0.12))
                        .overlay(Circle().stroke(themeForeground.opacity(0.1), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    private var sectionLabel: String {
        guard let ref = viewModel.session?.pageMap.pageRef(globalIndex: viewModel.currentGlobalIndex) else {
            return book.title
        }
        let title = viewModel.session?.document.chapters[safe: ref.chapterIndex]?.title ?? book.title
        if title.hasPrefix("引言") || title.lowercased().contains("introduction") {
            return "引言"
        }
        if title.isEmpty {
            return book.title
        }
        return "章节"
    }

    private var currentChapterTitle: String {
        guard let ref = viewModel.session?.pageMap.pageRef(globalIndex: viewModel.currentGlobalIndex),
              let title = viewModel.session?.document.chapters[safe: ref.chapterIndex]?.title,
              !title.isEmpty else {
            return book.title
        }
        return title
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Text("\(viewModel.currentGlobalIndex + 1) of \(viewModel.totalPages)")
                .tText(.meta, color: themeForeground.opacity(0.5))
                .monospacedDigit()
                .padding(.trailing, Spacing.sm)
        }
        .padding(.vertical, Spacing.sm)
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
        VStack(alignment: .trailing, spacing: Spacing.sm) {
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
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .tText(.button, color: themeForeground)
                Image(systemName: icon)
                    .tIcon(IconRole.control, weight: .semibold)
            }
            .foregroundStyle(themeForeground)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(themeForeground.opacity(0.12), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var overlayButtons: some View {
        VStack(alignment: .trailing, spacing: Spacing.md) {
            Spacer()
            if showMenu {
                readerMenu
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if book.hasAudio {
                circleButton(icon: "headphones") {
                    showListen = true
                    scheduleChromeHide()
                }
            }
            // 书签：已加则实心。点一下切换，不弹面板（对齐 Apple Books）。
            circleButton(icon: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark") {
                viewModel.toggleBookmark()
                scheduleChromeHide()
            }
            circleButton(icon: "list.bullet") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMenu.toggle()
                }
                scheduleChromeHide()
            }
        }
        .padding(Spacing.xl)
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
