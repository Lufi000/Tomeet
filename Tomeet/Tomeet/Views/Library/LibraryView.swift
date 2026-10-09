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
    @State private var showImporter = false
    @State private var deleteError: Error?
    @State private var catalog: InitialLibraryCatalog?

    private var sortedBooks: [Book] {
        let list = books.sorted { a, b in
            switch sortMode {
            case .recent: Book.sortRecentlyOpened(a, b)
            case .title: Book.sortTitle(a, b)
            case .author: Book.sortAuthor(a, b)
            case .manual: Book.sortManual(a, b)
            }
        }
        return list
    }

    private var booksByTheme: [(theme: InitialTheme, books: [Book])] {
        guard let catalog else { return [] }
        return catalog.themes.compactMap { theme in
            let themeBooks = sortedBooks.filter { $0.themes.contains(theme.id) }
            return themeBooks.isEmpty ? nil : (theme, themeBooks)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyState
                } else if groupMode == .all {
                    if viewMode == .grid {
                        gridContent(for: sortedBooks)
                    } else {
                        listContent(for: sortedBooks)
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
                    libraryMenu
                }
            }
            .fullScreenCover(item: $presentedListen) { book in
                ListenPlayerView(book: book)
            }
            .bookImportPresentation(isPresented: $showImporter)
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
                #endif
            }
        }
        .overlay { peekOverlay }
    }

    private var libraryMenu: some View {
        Menu {
            Button("Import Book...", systemImage: "square.and.arrow.down") {
                showImporter = true
            }
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
            Image(systemName: "ellipsis.circle")
        }
    }

    /// 页面顶部自定义大标题（字体用 `Font.book()`，与阅读器正文同一套衬线）
    private var libraryHeader: some View {
        Text("Library")
            .font(.book(.largeTitle, weight: .bold)).tracking(Theme.letterSpacing)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    /// 书架为空：插画 + 引导文案 + 导入入口。
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                libraryHeader
                Spacer(minLength: 40)
                Image("EmptyStateReading")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240)
                Text("No books yet")
                    .font(.book(.title3, weight: .bold)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                Text("Import a book and meet the mind inside.")
                    .font(.book(.subheadline)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    showImporter = true
                } label: {
                    Text("Import Book")
                        .font(.book(.headline)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .stroke(Theme.accent, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
        .scrollContentBackground(.hidden)
    }

    private var themedContent: some View {
        ScrollView {
            LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                libraryHeader
                ForEach(booksByTheme, id: \.theme.id) { section in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(section.books) { book in
                                BookGridCell(book: book) {
                                    openBook(book)
                                } onDelete: {
                                    bookToDelete = book
                                }
                            }
                        }
                    } header: {
                        themeHeader(section.theme)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
    }

    private func themeHeader(_ theme: InitialTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(theme.name)
                .font(.book(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.ink)
            Text(theme.description)
                .font(.book(.subheadline)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .background(Theme.canvas)
    }

    private func gridContent(for bookList: [Book]) -> some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                libraryHeader
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 24
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
    }

    private func listContent(for bookList: [Book]) -> some View {
        List(bookList) { book in
            Button {
                openBook(book)
            } label: {
                HStack(spacing: 12) {
                    BookCoverView(book: book)
                        .frame(width: 44)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: BookCoverFramePreferenceKey.self,
                                    value: [book.id: proxy.frame(in: .global)]
                                )
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.book(.body)).tracking(Theme.letterSpacing).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(book.author).font(.book(.caption)).tracking(Theme.letterSpacing).foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    if let progress = book.progressText {
                        Text(progress).font(.book(.caption)).tracking(Theme.letterSpacing).foregroundStyle(Theme.inkSecondary)
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
            libraryHeader
                .background(Theme.canvas)
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
