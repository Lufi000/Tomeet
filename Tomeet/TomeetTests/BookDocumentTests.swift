import Foundation
import Testing
@testable import Tomeet

struct BookDocumentTests {
    private func sampleDocument() -> BookDocument {
        let chapters = [
            Chapter(id: "ch1", title: "One", blocks: [
                .heading(level: 1, text: "Title"),
                .paragraph("Hello world"),
            ]),
            Chapter(id: "ch2", title: "Two", blocks: [
                .paragraph("Second chapter text"),
                .quote("A quoted line"),
            ]),
        ]
        return BookDocument(title: "Sample", author: nil, language: "en", chapters: chapters)
    }

    /// `textLength` 是**渲染后**的长度，含块间的 "\n" —— 与分页结果（NSRange）同一坐标系。
    /// 见 [CharacterSpaceTests] 里的不变量断言。
    @Test func textLengthCountsBlocksAndSeparators() {
        let chapter = Chapter(id: "x", title: "X", blocks: [.paragraph("abc"), .paragraph("def")])
        #expect(chapter.textLength == 7)   // "abc\ndef"
    }

    @Test func chapterStartsArePrefixSums() {
        let document = sampleDocument()
        // ch1 = "Title\nHello world" = 5+1+11 = 17；ch2 = "Second chapter text\nA quoted line" = 19+1+13 = 33
        #expect(document.chapterStarts == [0, 17, 50])
        #expect(document.totalCharacters == 50)
    }

    @Test func progressAtLocation() {
        let document = sampleDocument()
        #expect(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 0)) == 0)
        // 第 1 章末尾 = 17/50
        #expect(abs(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 16)) - 16.0 / 50.0) < 0.0001)
        // 越界回落
        #expect(abs(document.progress(at: ReaderLocation(chapterIndex: 9, charOffset: 999)) - 1.0) < 0.0001)
    }

    @Test func locationAtProgressClamps() {
        let document = sampleDocument()
        #expect(document.location(atProgress: 0.5) == ReaderLocation(chapterIndex: 1, charOffset: 8))
        #expect(document.location(atProgress: 0) == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(document.location(atProgress: 1) == ReaderLocation(chapterIndex: 1, charOffset: 33))
        #expect(document.location(atProgress: -1) == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(document.location(atProgress: 5) == ReaderLocation(chapterIndex: 1, charOffset: 33))
    }

    @Test func emptyBookReportsZero() {
        let empty = BookDocument(title: "", author: nil, language: nil, chapters: [])
        #expect(empty.totalCharacters == 0)
        #expect(empty.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 0)) == 0)
        #expect(empty.location(atProgress: 0.5) == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }

    @Test func emptyChapterProgress() {
        let document = BookDocument(title: "T", author: nil, language: nil, chapters: [Chapter(id: "a", title: "A", blocks: [])])
        #expect(document.totalCharacters == 0)
        #expect(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 0)) == 0)
        #expect(document.location(atProgress: 0.7) == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }
}
