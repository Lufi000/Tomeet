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

    /// Previous 书架排除 Continue 已展示的前 3 本，避免同一本书重复出现。
    private var previousBooks: [Book] {
        Array(recentlyOpened.dropFirst(continueBooks.count))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // iOS 26 的导航栏标题不吃 UIKit appearance，大字标题自己画
                    Text("Home")
                        .font(.splendid(.largeTitle, weight: .bold)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 16)

                    if !continueBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Continue")
                                .font(.splendid(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                                .foregroundStyle(Theme.ink)
                            ForEach(continueBooks) { book in
                                ContinueCard(book: book) {
                                    presentedReader = book
                                }
                            }
                        }
                    }

                    if !previousBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Previous")
                                .font(.splendid(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                                .foregroundStyle(Theme.ink)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(previousBooks) { book in
                                        Button {
                                            presentedReader = book
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                BookCoverView(book: book).frame(width: 100)
                                                Text(book.title)
                                                    .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                                                    .lineLimit(1)
                                                    .foregroundStyle(Theme.ink)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            // 不用系统大标题（字体无法定制），顶栏整体隐藏
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $presentedReader) { book in
                ReaderView(book: book)
            }
        }
    }
}
