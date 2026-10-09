import SwiftUI
import SwiftData

enum LibraryViewMode: String, CaseIterable {
    case grid
    case list
}

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recent, title, author, manual
    var id: String { rawValue }
}

enum LibraryGroupMode: String, CaseIterable, Identifiable {
    case all
    case byTheme

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .byTheme: return "By Theme"
        }
    }
}

struct LibraryView: View {
    @Query private var books: [Book]
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(BookOpening.self) private var bookOpening
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortMode: LibrarySortMode = .recent
    @State private var groupMode: LibraryGroupMode = .all
    @State private var presentedListen: Book?
    @State private var peekBook: Book?
    /// 各书籍封面在全局坐标系中的位置，由 `BookGridCell` / 列表行通过 preference 上报。
    @State private var coverFrames: [UUID: CGRect] = [:]
    @State private var bookToDelete: Book?
    @State private var showImportDialog = false
    @State private var showFileImporter = false
    @State private var isSearching = false
    @State private var searchText = ""
    /// 点搜索图标后直接把光标放进输入框 —— 不然要再点一次才能打字。
    @FocusState private var isSearchFieldFocused: Bool
    @State private var deleteError: Error?
    @State private var catalog: InitialLibraryCatalog?

    /// 常驻欢迎语 —— 有书没书都显示（已确认的产品决定）。
    private static let welcomeTitle = "Welcome to the Book Store."
    private static let welcomeSubtitle =
        "You can live your whole life without ever noticing the beauty of the world around you. Reading lets you glimpse it."

    private var sortedBooks: [Book] {
        books.sorted { a, b in
            switch sortMode {
            case .recent: Book.sortRecentlyOpened(a, b)
            case .title: Book.sortTitle(a, b)
            case .author: Book.sortAuthor(a, b)
            case .manual: Book.sortManual(a, b)
            }
        }
    }

    /// 搜索只过滤本地书架：书名 / 作者 / 主题名。
    /// **不做正文全文检索** —— 那是另一个子系统。
    private var visibleBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sortedBooks }
        return sortedBooks.filter { book in
            if book.title.localizedStandardContains(query) { return true }
            if book.author.localizedStandardContains(query) { return true }
            return themeNames(of: book).contains { $0.localizedStandardContains(query) }
        }
    }

    private func themeNames(of book: Book) -> [String] {
        guard let catalog else { return [] }
        return catalog.themes.filter { book.themes.contains($0.id) }.map(\.name)
    }

    private var booksByTheme: [(theme: InitialTheme, books: [Book])] {
        guard let catalog else { return [] }
        return catalog.themes.compactMap { theme in
            let themeBooks = visibleBooks.filter { $0.themes.contains(theme.id) }
            return themeBooks.isEmpty ? nil : (theme, themeBooks)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyState
                } else if Self.hasNothingToShow(
                    visibleCount: visibleBooks.count,
                    themeSectionCount: booksByTheme.count,
                    groupByTheme: groupMode == .byTheme
                ) {
                    // 三条内容路径共用这一个判断 —— 之前只有网格那条接了空态，
                    // 切到列表或按主题再搜索就白屏（spec §5.5：不是空白）。
                    noResultsScreen
                } else if groupMode == .all {
                    if viewMode == .grid {
                        gridContent(for: visibleBooks)
                    } else {
                        listContent(for: visibleBooks)
                    }
                } else {
                    themedContent
                }
            }
            .background(Theme.canvas)
            // 系统大标题字体无法定制（iOS 26 不吃 UIKit appearance），标题自己画
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    libraryActions
                }
            }
            .fullScreenCover(item: $presentedListen) { book in
                ListenPlayerView(book: book)
            }
            .bookImportPresentation(isPresented: $showFileImporter)
            .confirmationDialog(
                "Import Books",
                isPresented: $showImportDialog,
                titleVisibility: .visible
            ) {
                Button("iCloud") { showFileImporter = true }
                // 第二轮（Wi-Fi 局域网传输）在这里加一行 Button("Wi-Fi") { … }。
                //
                // 本轮**不放**禁用态的 Wi-Fi 行：实测确认 SwiftUI 的
                // `confirmationDialog` 会把 `.disabled(true)` 的按钮**整个丢掉**
                // （不是变灰）—— 放上去用户根本看不见，也就谈不上「入口位置一次到位」。
                // 第二轮那行本身就是 1 行代码，届时补上没有额外 UI 改动。
            } message: {
                Text(BookImporter.importDialogMessage)
            }
            .alert("Remove Failed", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError?.localizedDescription ?? "Unknown error")
            }
            .confirmationDialog("Remove Book", isPresented: Binding(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                }
                Button("Cancel", role: .cancel) {
                    bookToDelete = nil
                }
            } message: {
                if let book = bookToDelete {
                    Text("“\(book.title)” will be removed from your library.")
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // 弹层期间收起 TabBar：否则内容区被它切掉一截，卡片会按「整屏」算尺寸、
            // 却按「去掉 TabBar 的那块」定位，于是看着不居中，底部按钮还会被压住。
            .toolbar(peekBook == nil ? .visible : .hidden, for: .tabBar)
            .onPreferenceChange(BookCoverFramePreferenceKey.self) { coverFrames = $0 }
            .task {
                catalog = try? InitialLibraryLoader.load()
                #if DEBUG
                openPeekForSnapshotIfRequested()
                openBookForSnapshotIfRequested()
                openSearchForSnapshotIfRequested()
                openImportForSnapshotIfRequested()
                #endif
            }
        }
        .overlay { peekOverlay }
    }

    // MARK: - 顶栏右侧

    /// 三个图标：`[搜索] [导入] [更多]`。
    ///
    /// 导入在**第二位**是有意的 —— 设计稿「右上方第二个按钮 WIFI导入 icloud 导入」
    /// 说的就是它。第三个「更多」是设计稿没覆盖的部分：现有菜单里
    /// Select / View / Sort / Group / Remove Downloads 需要一个落点。
    private var libraryActions: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                isSearching = true
                // 搜索框要在同一帧里才被建出来，直接置 true 会被丢掉 —— 等一拍。
                Task { @MainActor in isSearchFieldFocused = true }
            } label: {
                Image(systemName: "magnifyingglass").tIcon(IconRole.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            Button {
                showImportDialog = true
            } label: {
                Image(systemName: "square.and.arrow.down").tIcon(IconRole.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import books")

            libraryMenu
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(Capsule().fill(Theme.card))
    }

    private var libraryMenu: some View {
        Menu {
            Button("Select", systemImage: "checkmark.circle") {
                // M2 编辑模式（§3.4）
            }
            Divider()
            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(LibraryViewMode.grid)
                Image(systemName: "list.bullet").tag(LibraryViewMode.list)
            }
            Picker("Sort by", selection: $sortMode) {
                Text("Recent").tag(LibrarySortMode.recent)
                Text("Title").tag(LibrarySortMode.title)
                Text("Author").tag(LibrarySortMode.author)
                Text("Manual").tag(LibrarySortMode.manual)
            }
            Picker("Group by", selection: $groupMode) {
                Text(LibraryGroupMode.all.label).tag(LibraryGroupMode.all)
                Text(LibraryGroupMode.byTheme.label).tag(LibraryGroupMode.byTheme)
            }
            Divider()
            Button("Remove Downloads", systemImage: "icloud.slash") {
                // M1 占位
            }
            .disabled(true)
        } label: {
            Image(systemName: "ellipsis").tIcon(IconRole.control)
        }
        .accessibilityLabel("More options")
    }

    // MARK: - 页头

    @ViewBuilder
    private var header: some View {
        if isSearching {
            searchHeader
        } else {
            TPageHeader(Self.welcomeTitle, subtitle: Self.welcomeSubtitle)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .tIcon(IconRole.control)
                .foregroundStyle(Theme.inkSecondary)
            TextField("Search books", text: $searchText)
                .tText(.body)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .tIcon(IconRole.control)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
            }
            Button("Cancel") {
                isSearching = false
                searchText = ""
            }
            .tText(.button, color: Theme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - 内容

    /// 书架为空：页头已经说了欢迎语，这里只剩插画 + 一句引导 + 按钮。
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                header
                Spacer(minLength: Spacing.xl)
                TEmptyState(
                    illustration: "EmptyStateReading",
                    message: "Import a book and meet the mind inside."
                ) {
                    TButton("Import Book", style: .secondary) {
                        showImportDialog = true
                    }
                }
                Spacer(minLength: Spacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    private var themedContent: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.lg, pinnedViews: [.sectionHeaders]) {
                header
                ForEach(booksByTheme, id: \.theme.id) { section in
                    Section {
                        bookGrid(section.books)
                            .padding(.horizontal, Spacing.md)
                    } header: {
                        themeHeader(section.theme)
                    }
                }
            }
            .padding(.top, Spacing.sm)
        }
        .scrollContentBackground(.hidden)
    }

    private func themeHeader(_ theme: InitialTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(theme.name).tText(.sectionTitle)
            Text(theme.description)
                .tText(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Theme.canvas)
    }

    private func gridContent(for bookList: [Book]) -> some View {
        ScrollView {
            LazyVStack(spacing: Spacing.lg) {
                header
                // 横向边距挂在网格上，不是挂在外层 VStack 上：
                // `TPageHeader` 自带 md 边距，套在外层会让标题变成 48pt、
                // 而网格还是 24pt —— 同一页两个左边距。列表与空态没有外层，
                // 于是标题还会在切换模式时横跳 24pt。
                bookGrid(bookList)
                    .padding(.horizontal, Spacing.md)
            }
            .padding(.top, Spacing.sm)
        }
        .scrollContentBackground(.hidden)
    }

    /// 两列等宽。设计稿用了 `justify-between`，导致两本书的封面宽度不同（147 / 134）——
    /// 那是稿子自身的不一致，不照抄。
    private func bookGrid(_ bookList: [Book]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.md),
                GridItem(.flexible(), spacing: Spacing.md),
            ],
            spacing: Spacing.hero
        ) {
            ForEach(bookList) { book in
                BookGridCell(book: book) {
                    openBook(book)
                } onDelete: {
                    bookToDelete = book
                }
            }
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 三条内容路径**共用**的判断点。抽成 static 是为了能被测试钉住 ——
    /// 这条判断原先只存在于网格那条路径里。
    static func hasNothingToShow(
        visibleCount: Int,
        themeSectionCount: Int,
        groupByTheme: Bool
    ) -> Bool {
        groupByTheme ? themeSectionCount == 0 : visibleCount == 0
    }

    private var noResultsScreen: some View {
        Text(isFiltering ? "No books match “\(searchText)”." : "No books in this view.")
            .tText(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.hero)
    }

    private func listContent(for bookList: [Book]) -> some View {
        List(bookList) { book in
            Button {
                openBook(book)
            } label: {
                HStack(spacing: Spacing.sm) {
                    BookCoverView(book: book)
                        .frame(width: Spacing.xl)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: BookCoverFramePreferenceKey.self,
                                    value: [book.id: proxy.frame(in: .global)]
                                )
                            }
                        }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(book.title).tText(.body).lineLimit(1)
                        Text(book.author).tText(.meta)
                    }
                    Spacer()
                    if let progress = book.progressText {
                        Text(progress).tText(.meta)
                    }
                }
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteBook(book)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            header.background(Theme.canvas)
        }
    }

    /// 未读（NEW）书先弹详情卡片；读过的书直接翻开 —— 封面从这一格的原位抬起、绕书脊
    /// 荡开，底下露出上次读到的那一页（动效由 `RootView` 上的呈现层负责）。
    private func openBook(_ book: Book) {
        if book.showsNewBadge {
            peekBook = book
        } else {
            bookOpening.open(book, from: coverFrames[book.id])
        }
    }

    #if DEBUG
    /// 仅供录屏验证：`xcrun simctl launch <udid> com.ivy.Tomeet --ui-snapshot-peek`
    /// 会自动点开书架里第一本未读书的弹层。
    ///
    /// 模拟器没有可编程的点击接口，不自己触发就录不到「从封面原位翻起」那几帧 ——
    /// 而这次改的正是那几帧。延迟 1.5s 是为了等网格上报完封面坐标，
    /// 走的是和手指点完全同一条路径（真回调、真 frame）。
    private func openPeekForSnapshotIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-peek"),
              let book = sortedBooks.first(where: \.showsNewBadge) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            peekBook = book
        }
    }

    /// 仅供录屏验证：`xcrun simctl launch <udid> com.ivy.Tomeet --ui-snapshot-open`
    /// 会点开书架里第一本**有进度**的书 —— 走的正是这次改的那条路径
    /// （抬起 → 翻开 → 底下是正文而不是转圈）。
    ///
    /// 全新安装时得先给它一点进度：种子里 42 本全是 NEW（零进度），
    /// 而 NEW 的书走的是弹层那条路，挑 `!showsNewBadge` 会一本都挑不到 ——
    /// 钩子静默失效，录到一张静止画面，然后得出"动画没跑"的错误结论。
    private func openBookForSnapshotIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-open"),
              let book = sortedBooks.first else { return }
        if book.showsNewBadge {
            book.readingProgress = 0.35
            try? modelContext.save()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            openBook(book)
        }
    }

    /// 仅供录屏验证：`--ui-snapshot-search <关键词>` 直接进入搜索态并填入关键词。
    /// 传一个搜不到的词就能同时验收「无结果」那一屏。
    private func openSearchForSnapshotIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--ui-snapshot-search"), i + 1 < args.count else { return }
        isSearching = true
        searchText = args[i + 1]
    }

    /// 仅供录屏验证：`--ui-snapshot-import` 直接拉起导入 Action Sheet。
    private func openImportForSnapshotIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-import") else { return }
        showImportDialog = true
    }
    #endif

    /// 未读书籍弹层；收放动画由弹层自管理，父视图只负责装/卸。
    @ViewBuilder
    private var peekOverlay: some View {
        if let book = peekBook {
            UnreadBookPeekView(
                book: book,
                sourceFrame: coverFrames[book.id],
                onDismiss: { peekBook = nil },
                // 弹层自己会先翻回收起（`dismiss` 等沉降完才回调），这里接着
                // 从书架上那一格把书翻开 —— 两拍首尾相接，是一条连续的路径。
                // `peekBook = nil` 不能省：弹层停在 t=0 时虽然全透明，但仍然挂在那儿挡手势。
                onStartReading: {
                    peekBook = nil
                    bookOpening.open(book, from: coverFrames[book.id])
                },
                onListen: {
                    peekBook = nil
                    presentedListen = book
                },
                onRemove: { bookToDelete = book }
            )
        }
    }

    private func deleteBook(_ book: Book) {
        // 若正在播放本书的音频，先停止并卸载播放器，避免删书后仍在播放
        audioPlayer.unloadIfCurrent(bookID: book.id)
        do {
            try BookDeletionService.delete(book: book, modelContext: modelContext)
        } catch {
            deleteError = error
        }
        bookToDelete = nil
    }
}
