import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct ModelTests {
    @Test func bookInsertsAndFetches() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let book = Book(title: "测试书", author: "作者", format: .epub)
        context.insert(book)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>(
            predicate: #Predicate { $0.title == "测试书" }
        ))
        #expect(fetched.count == 1)
        #expect(fetched.first?.author == "作者")
        #expect(fetched.first?.format == .epub)
    }

    @Test func bookDefaultsMatchSpec() {
        let book = Book(title: "T", author: "A", format: .pdf)
        #expect(book.readingProgress == 0)
        #expect(book.isNew)
        #expect(book.isDownloaded)
        #expect(book.lastOpenedDate == nil)
        #expect(book.collection == nil)
        #expect(book.sourceFileName == nil)
        #expect(book.currentLocation == nil)
        #expect(book.themes.isEmpty)
        #expect(book.catalogID == nil)
    }

    @Test func newFieldsDefaultToNil() {
        let book = Book(title: "T", author: "A", format: .epub)
        #expect(book.sourceFileName == nil)
        #expect(book.currentLocation == nil)
        #expect(book.themes.isEmpty)
        #expect(book.catalogID == nil)
    }

    @Test func readerFieldsPersistRoundTrip() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let book = Book(title: "T", author: "A", format: .epub)
        book.sourceFileName = "george-macdonald_if-i-had-a-father"
        book.currentLocation = "3:4821"
        book.themes = ["know-yourself", "freedom-and-responsibility"]
        book.catalogID = "test-book"
        context.insert(book)
        try context.save()
        let fetch = FetchDescriptor<Book>()
        let fetched = try #require(try context.fetch(fetch).first)
        #expect(fetched.sourceFileName == "george-macdonald_if-i-had-a-father")
        #expect(fetched.currentLocation == "3:4821")
        #expect(fetched.themes == ["know-yourself", "freedom-and-responsibility"])
        #expect(fetched.catalogID == "test-book")
    }

    @Test func audioFieldsDefaultToNil() {
        let book = Book(title: "T", author: "A", format: .epub)
        #expect(book.audioFileName == nil)
        #expect(book.listenPosition == nil)
        #expect(book.audioAlignmentFileName == nil)
        #expect(book.hasAudio == false)
    }

    @Test func hasAudioReflectsAudioFileName() {
        let book = Book(title: "T", author: "A", format: .epub)
        book.audioFileName = "jiangshu.mp3"
        #expect(book.hasAudio == true)
    }

    @Test func formatLabels() {
        #expect(BookFormat.epub.label == "EPUB")
        #expect(BookFormat.pdf.label == "PDF")
        #expect(BookFormat.mobi.label == "MOBI")
        #expect(BookFormat.audiobook.label == "Audiobook")
        #expect(BookFormat.allCases.count == 4)
    }
}
