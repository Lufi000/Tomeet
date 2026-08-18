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

struct LibraryView: View {
    @Query private var books: [Book]
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortMode: LibrarySortMode = .recent
    @State private var showCollections = false
    @State private var presentedReader: Book?

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

    var body: some View {
        NavigationStack {
            Group {
                if viewMode == .grid {
                    gridContent
                } else {
                    listContent
                }
            }
            .background(Color(.systemGray6)) // 页面默认深色系背景（§3.1）
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Collections") {
                        showCollections = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    libraryMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 预留后续更多操作（§3.1）
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showCollections) {
                CollectionsSheet(books: books)
            }
            .fullScreenCover(item: $presentedReader) { book in
                ReaderView(book: book)
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
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
            Divider()
            Button("Remove Downloads", systemImage: "icloud.slash") {
                // M1 占位
            }
            .disabled(true)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 24
            ) {
                ForEach(sortedBooks) { book in
                    BookGridCell(book: book) {
                        presentedReader = book
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var listContent: some View {
        List(sortedBooks) { book in
            Button {
                presentedReader = book
            } label: {
                HStack(spacing: 12) {
                    BookCoverView(book: book).frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.body).lineLimit(1)
                        Text(book.author).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let progress = book.progressText {
                        Text(progress).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}
