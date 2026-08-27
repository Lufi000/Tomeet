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
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortMode: LibrarySortMode = .recent
    @State private var groupMode: LibraryGroupMode = .all
    @State private var presentedReader: Book?
    @State private var bookToDelete: Book?
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var importError: Error?
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
                if groupMode == .all {
                    if viewMode == .grid {
                        gridContent(for: sortedBooks)
                    } else {
                        listContent(for: sortedBooks)
                    }
                } else {
                    themedContent
                }
            }
            .background(Color(.systemGray6)) // 页面默认深色系背景（§3.1）
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    libraryMenu
                }
            }
            .fullScreenCover(item: $presentedReader) { book in
                switch book.format {
                case .pdf:
                    PDFReaderView(book: book)
                case .mobi:
                    MobiReaderView(book: book)
                case .epub, .audiobook:
                    ReaderView(book: book)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: BookImporter.supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                Task {
                    isImporting = true
                    defer { isImporting = false }
                    do {
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            _ = try await BookImporter.importBook(from: url, modelContext: modelContext)
                        case .failure(let error):
                            throw error
                        }
                    } catch {
                        importError = error
                    }
                }
            }
            .overlay {
                if isImporting {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 160, height: 120)
                        .overlay {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Importing...")
                                    .font(.subheadline)
                            }
                        }
                }
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError?.localizedDescription ?? "Unknown error")
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
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                catalog = try? InitialLibraryLoader.load()
            }
        }
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

    private var themedContent: some View {
        ScrollView {
            LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(booksByTheme, id: \.theme.id) { section in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(section.books) { book in
                                BookGridCell(book: book) {
                                    presentedReader = book
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
    }

    private func themeHeader(_ theme: InitialTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(theme.name)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(theme.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private func gridContent(for bookList: [Book]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 24
            ) {
                ForEach(bookList) { book in
                    BookGridCell(book: book) {
                        presentedReader = book
                    } onDelete: {
                        bookToDelete = book
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func listContent(for bookList: [Book]) -> some View {
        List(bookList) { book in
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
