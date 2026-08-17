import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @Query private var goals: [ReadingGoal]
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

                    ReadingGoalsSection(goal: goals.first)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ReadingGoalsDetailPlaceholder(goal: goals.first)
                    } label: {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 头像入口，M1 占位
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                    }
                }
            }
            .fullScreenCover(item: $presentedReader) { book in
                ReaderPlaceholderView(book: book)
            }
        }
    }
}

/// Reading Goals 详情占位页（mvp.md §2.1 顶部入口）。
struct ReadingGoalsDetailPlaceholder: View {
    let goal: ReadingGoal?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Today") {
                if let goal {
                    LabeledContent("Time spent", value: goal.todayTimeText)
                    LabeledContent("Goal", value: goal.goalText)
                    LabeledContent("Streak", value: "\(goal.currentStreak) days")
                } else {
                    Text("No reading goal yet")
                }
            }
        }
        .navigationTitle("Reading Goals")
        .navigationBarTitleDisplayMode(.inline)
    }
}
