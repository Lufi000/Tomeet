import Foundation
import Testing
@testable import Tomeet

@MainActor
struct DisplayTests {
    private func book(
        readingProgress: Double = 0,
        isNew: Bool = true,
        isDownloaded: Bool = true,
        addedDate: Date = .distantPast,
        lastOpenedDate: Date? = nil
    ) -> Book {
        Book(
            title: "B", author: "A", format: .epub,
            addedDate: addedDate, lastOpenedDate: lastOpenedDate,
            readingProgress: readingProgress, isNew: isNew, isDownloaded: isDownloaded
        )
    }

    @Test func newBadgeIsNewAndZeroProgress() {
        #expect(book(readingProgress: 0, isNew: true).showsNewBadge)
        #expect(!book(readingProgress: 0.5, isNew: true).showsNewBadge)
        #expect(!book(readingProgress: 0, isNew: false).showsNewBadge)
    }

    @Test func progressTextExcludesNew() {
        #expect(book(readingProgress: 0.07).progressText == "7%")
        #expect(book(readingProgress: 1.0).progressText == "100%")
        #expect(book(readingProgress: 0, isNew: true).progressText == nil)
        // 非 new 的 0% 不是 NEW，显示 0%
        #expect(book(readingProgress: 0, isNew: false).progressText == "0%")
    }

    @Test func downloadIconOnlyWhenNotDownloaded() {
        #expect(book(isDownloaded: false).needsDownloadIcon)
        #expect(!book(isDownloaded: true).needsDownloadIcon)
    }

    @Test func sorting() {
        let recent = book(addedDate: .distantPast, lastOpenedDate: Date(timeIntervalSinceNow: -100))
        let older = book(addedDate: .distantPast, lastOpenedDate: Date(timeIntervalSinceNow: -5000))
        let never = book(addedDate: .distantPast, lastOpenedDate: nil)
        #expect(Book.sortRecentlyOpened(recent, older))
        #expect(Book.sortRecentlyOpened(recent, never))

        let a = book(addedDate: .distantPast)
        let b = Book(title: "Zebra", author: "A", format: .epub, addedDate: .distantPast)
        #expect(Book.sortTitle(a, b))
        #expect(Book.sortAuthor(Book(title: "X", author: "Alpha", format: .epub, addedDate: .distantPast), Book(title: "Y", author: "Beta", format: .epub, addedDate: .distantPast)))
        #expect(Book.sortAuthor(b, a) == false)

        let earlier = book(addedDate: Date(timeIntervalSince1970: 10))
        let later = book(addedDate: Date(timeIntervalSince1970: 20))
        #expect(Book.sortManual(earlier, later))
    }

    @Test func clockFormatsAsMMSS() {
        #expect(ReadingGoal.clockString(seconds: 71) == "1:11")
        #expect(ReadingGoal.clockString(seconds: 0) == "0:00")
        #expect(ReadingGoal.clockString(seconds: 3600) == "60:00")
    }

    @Test func readingGoalDisplay() {
        let goal = ReadingGoal(dailyGoalMinutes: 5, todayReadingSeconds: 71)
        #expect(goal.todayProgress > 0 && goal.todayProgress < 1)
        #expect(goal.todayTimeText == "1:11")
        #expect(goal.goalText == "of your 5-minute goal")
    }
}
