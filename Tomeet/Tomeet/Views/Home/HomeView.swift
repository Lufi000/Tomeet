import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @Query private var dailyReadings: [DailyReading]
    @State private var presentedReader: Book?

    /// 今日（本地时区 0 点起）的时长记录；没有则 nil。
    private var todayReading: DailyReading? {
        let start = Calendar.current.startOfDay(for: Date())
        return dailyReadings.first { $0.date == start }
    }

    private var recentlyOpened: [Book] {
        books.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
    }

    private var continueBooks: [Book] {
        Array(recentlyOpened.prefix(3))
    }

    /// Continue 里前 3 本之后的书，以封面书架形式接在大卡片下方。
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

                    todayStatsCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Continue")
                            .font(.splendid(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                            .foregroundStyle(Theme.ink)
                        if continueBooks.isEmpty {
                            continueEmptyCard
                        } else {
                            ForEach(continueBooks) { book in
                                ContinueCard(book: book) {
                                    presentedReader = book
                                }
                            }
                            if !previousBooks.isEmpty {
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

    // MARK: - 今日时长

    private var todayStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.splendid(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 0) {
                statColumn(image: "TodayReading", title: "Reading", seconds: todayReading?.readSeconds ?? 0)
                Rectangle()
                    .fill(Theme.inkFaint)
                    .frame(width: 1, height: 40)
                statColumn(image: "TodayListening", title: "Listening", seconds: todayReading?.listenSeconds ?? 0)
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.card)
            )
        }
    }

    private func statColumn(image: String, title: String, seconds: TimeInterval) -> some View {
        VStack(spacing: 6) {
            Image(image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 52)
            Text(timeText(seconds))
                .font(.splendid(.headline, weight: .semibold)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(title)
                .font(.splendid(.caption2)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Continue 空状态：刺猬插画 + 提示文案。
    private var continueEmptyCard: some View {
        VStack(spacing: 10) {
            Image("EmptyStateContinue")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 110)
            Text("Books you start reading will appear here.")
                .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
        )
    }

    /// 满 1 小时显示 "Xh Y min"，否则显示 "N min"。
    private func timeText(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        guard totalMinutes > 0 else { return "0 min" }
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60) min"
        }
        return "\(totalMinutes) min"
    }
}
