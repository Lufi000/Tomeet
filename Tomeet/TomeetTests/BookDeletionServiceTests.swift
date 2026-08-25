import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct BookDeletionServiceTests {
    @Test func deleteRemovesBookFromModelContext() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let book = Book(title: "To Delete", author: "Author", format: .epub)
        context.insert(book)
        try context.save()

        try BookDeletionService.delete(book: book, modelContext: context)

        let fetched = try context.fetch(FetchDescriptor<Book>())
        #expect(fetched.isEmpty)
    }

    @Test func deleteRemovesApplicationSupportDirectory() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let bookID = UUID()
        let book = Book(id: bookID, title: "To Delete", author: "Author", format: .epub)
        book.sourceFileName = bookID.uuidString
        context.insert(book)
        try context.save()

        let bookDir = BookSourceResolver.directoryURL(forSourceFileName: bookID.uuidString)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        let markerFile = bookDir.appendingPathComponent("marker.txt")
        try "test".write(to: markerFile, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: bookDir.path))

        try BookDeletionService.delete(book: book, modelContext: context)

        #expect(!FileManager.default.fileExists(atPath: bookDir.path))
    }

    @Test func deleteLeavesBundledBooksUnchanged() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let book = Book(title: "Bundled", author: "Author", format: .epub)
        book.sourceFileName = "bundled-book-name"
        context.insert(book)
        try context.save()

        try BookDeletionService.delete(book: book, modelContext: context)

        let fetched = try context.fetch(FetchDescriptor<Book>())
        #expect(fetched.isEmpty)
    }
}
