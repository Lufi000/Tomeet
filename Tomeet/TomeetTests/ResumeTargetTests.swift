import Foundation
import Testing
@testable import Tomeet

/// 启动续读：打开 App 应该回到在读的那本书、那一页。
struct ResumeTargetTests {
    private func makeBook(
        _ title: String,
        openedDaysAgo: Double?,
        location: ReaderLocation? = nil
    ) -> Book {
        let book = Book(title: title, author: "A", format: .epub)
        if let openedDaysAgo {
            book.lastOpenedDate = Date(timeIntervalSinceNow: -openedDaysAgo * 86_400)
        }
        book.currentLocation = location?.encoded
        return book
    }

    @Test func picksMostRecentlyOpenedResumableBook() {
        let old = makeBook("Old", openedDaysAgo: 3, location: ReaderLocation(chapterIndex: 2, charOffset: 10))
        let recent = makeBook("Recent", openedDaysAgo: 1, location: ReaderLocation(chapterIndex: 5, charOffset: 900))
        #expect(ResumeTarget.book(in: [old, recent])?.title == "Recent")
    }

    @Test func skipsBooksWithoutReadingPosition() {
        // 最近打开过，但从没读到过（点开就退）—— 不该自动进。
        let touched = makeBook("Touched", openedDaysAgo: 1)
        let read = makeBook("Read", openedDaysAgo: 9, location: ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(ResumeTarget.book(in: [touched, read])?.title == "Read")
    }

    @Test func skipsUnparsableLocation() {
        // 旧版本可能写坏 currentLocation；坏值不能拦住启动，也不能当成可续读。
        let broken = Book(title: "Broken", author: "A", format: .epub)
        broken.lastOpenedDate = Date()
        broken.currentLocation = "not-a-location"
        #expect(ResumeTarget.book(in: [broken]) == nil)
    }

    @Test func noResumableBookReturnsNil() {
        #expect(ResumeTarget.book(in: []) == nil)
        #expect(ResumeTarget.book(in: [makeBook("Untouched", openedDaysAgo: nil)]) == nil)
    }
}
