import Foundation
import Testing
@testable import Tomeet

struct ReaderPageMapTests {
    /// 三章、每章 2/3/1 页的最小分页结果（手工构造，不依赖 TextKit）。
    private func fixture() -> ReaderPageMap {
        let chapters = [
            PaginatedChapter(chapterIndex: 0, pages: [
                TextPage(text: .init(string: "a"), characterRange: NSRange(location: 0, length: 5)),
                TextPage(text: .init(string: "b"), characterRange: NSRange(location: 5, length: 5)),
            ]),
            PaginatedChapter(chapterIndex: 1, pages: [
                TextPage(text: .init(string: "c"), characterRange: NSRange(location: 0, length: 4)),
                TextPage(text: .init(string: "d"), characterRange: NSRange(location: 4, length: 4)),
                TextPage(text: .init(string: "e"), characterRange: NSRange(location: 8, length: 4)),
            ]),
            PaginatedChapter(chapterIndex: 2, pages: [
                TextPage(text: .init(string: "f"), characterRange: NSRange(location: 0, length: 7)),
            ]),
        ]
        return ReaderPageMap(chapterPages: chapters)
    }

    @Test func totalPagesAndStartPageTable() {
        let map = fixture()
        #expect(map.totalPages == 6)
        #expect(map.chapterStartPage == [0, 2, 5, 6])
    }

    @Test func globalIndexRoundTrip() {
        let map = fixture()
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 0, pageInChapter: 1)) == 1)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 1, pageInChapter: 0)) == 2)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 2, pageInChapter: 0)) == 5)
        #expect(map.pageRef(globalIndex: 4) == PageRef(chapterIndex: 1, pageInChapter: 2))
        #expect(map.pageRef(globalIndex: 0) == PageRef(chapterIndex: 0, pageInChapter: 0))
        #expect(map.pageRef(globalIndex: 6) == nil)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 3, pageInChapter: 0)) == nil)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 0, pageInChapter: 9)) == nil)
    }

    @Test func textPageByGlobalIndex() {
        let map = fixture()
        #expect(map.textPage(globalIndex: 3)?.characterRange == NSRange(location: 4, length: 4))
        #expect(map.textPage(globalIndex: 5)?.characterRange == NSRange(location: 0, length: 7))
        #expect(map.textPage(globalIndex: 99) == nil)
    }

    @Test func charOffsetFindsPage() {
        let map = fixture()
        #expect(map.pageRef(chapterIndex: 0, charOffset: 0) == PageRef(chapterIndex: 0, pageInChapter: 0))
        #expect(map.pageRef(chapterIndex: 0, charOffset: 4) == PageRef(chapterIndex: 0, pageInChapter: 0))
        #expect(map.pageRef(chapterIndex: 0, charOffset: 5) == PageRef(chapterIndex: 0, pageInChapter: 1))
        #expect(map.pageRef(chapterIndex: 1, charOffset: 9) == PageRef(chapterIndex: 1, pageInChapter: 2))
        #expect(map.pageRef(chapterIndex: 1, charOffset: 12) == PageRef(chapterIndex: 1, pageInChapter: 2))  // 章末尾等同最后一页
        #expect(map.pageRef(chapterIndex: 9, charOffset: 0) == nil)
    }

    @Test func sessionConvertsLocationAndGlobalIndex() {
        let session = ReaderSession(
            document: BookDocument(title: "T", author: nil, language: nil, chapters: [
                Chapter(id: "a", title: "Alpha", blocks: [.paragraph("0123456789")]),   // 10 字符
                Chapter(id: "b", title: "Beta", blocks: [.paragraph("abcdefghij")]),     // 10 字符
            ]),
            pageMap: ReaderPageMap(chapterPages: [
                PaginatedChapter(chapterIndex: 0, pages: [
                    TextPage(text: .init(), characterRange: NSRange(location: 0, length: 6)),
                    TextPage(text: .init(), characterRange: NSRange(location: 6, length: 4)),
                ]),
                PaginatedChapter(chapterIndex: 1, pages: [
                    TextPage(text: .init(), characterRange: NSRange(location: 0, length: 10)),
                ]),
            ])
        )
        #expect(session.totalPages == 3)
        #expect(session.chapterTitles == ["Alpha", "Beta"])
        #expect(session.location(forGlobalIndex: 1) == ReaderLocation(chapterIndex: 0, charOffset: 6))
        #expect(session.globalIndex(for: ReaderLocation(chapterIndex: 1, charOffset: 3)) == 2)
        #expect(session.globalIndex(for: ReaderLocation(chapterIndex: 0, charOffset: 8)) == 1)
    }
}
