import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @State private var presentedReader: Book?

    private var recentlyOpened: [Book] {
        books.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
    }

    private var continueBooks: [Book] {
        Array(recentlyOpened.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !continueBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Continue").font(.title2.bold())
                            ForEach(continueBooks) { book in
                                ContinueCard(book: book) {
                                    presentedReader = book
                                }
                            }
                        }
                    }

                    if !recentlyOpened.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Previous").font(.title2.bold())
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(recentlyOpened) { book in
                                        Button {
                                            presentedReader = book
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                BookCoverView(book: book).frame(width: 100)
                                                Text(book.title)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                    .foregroundStyle(.primary)
                                            }
                                            .frame(width: 100)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(item: $presentedReader) { book in
                ReaderView(book: book)
            }
        }
    }
}
