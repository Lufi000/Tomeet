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

    @Test func textLengthCountsBlocks() {
        let chapter = Chapter(id: "x", title: "X", blocks: [.paragraph("abc"), .paragraph("def")])
        #expect(chapter.textLength == 6)
    }

    @Test func chapterStartsArePrefixSums() {
        let document = sampleDocument()
        // ch1 = "Title"(5) + "Hello world"(11) → 16；ch2 = "Second chapter text"(19) + "A quoted line"(13) → 32
        #expect(document.chapterStarts == [0, 16, 48])
        #expect(document.totalCharacters == 48)
    }

    @Test func progressAtLocation() {
        let document = sampleDocument()
        #expect(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 0)) == 0)
        // 第 1 章末尾 = 16/48
        #expect(abs(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 16)) - 16.0 / 48.0) < 0.0001)
        // 越界回落
        #expect(abs(document.progress(at: ReaderLocation(chapterIndex: 9, charOffset: 999)) - 1.0) < 0.0001)
    }

    @Test func locationAtProgressClamps() {
        let document = sampleDocument()
        #expect(document.location(atProgress: 0.5) == ReaderLocation(chapterIndex: 1, charOffset: 8))
        #expect(document.location(atProgress: 0) == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(document.location(atProgress: 1) == ReaderLocation(chapterIndex: 1, charOffset: 32))
        #expect(document.location(atProgress: -1) == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(document.location(atProgress: 5) == ReaderLocation(chapterIndex: 1, charOffset: 32))
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
