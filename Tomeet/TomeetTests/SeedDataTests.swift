import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct SeedDataTests {
    @Test func fixtureHasOneRealBook() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        try SeedData.seedIfNeeded(in: container.mainContext)
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.allSatisfy { $0.sourceFileName != nil })
        #expect(books.allSatisfy { !$0.themes.isEmpty })
        #expect(books.allSatisfy { $0.catalogID != nil })
        #expect(books.allSatisfy { $0.format == .epub })

        let catalog = try InitialLibraryLoader.load()
        #expect(catalog.books.count == 1)
    }

    @Test func legacyFakeBooksAreRebuilt() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        // 手工种入「假书特征」：Book 非空且无任何 sourceFileName
        let fake = Book(title: "旧假书", author: "某作者", format: .epub)
        context.insert(fake)
        try context.save()

        try SeedData.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.allSatisfy { $0.sourceFileName != nil })
    }

    @Test func realBooksAreNotReplacedByRebuild() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedData.seedIfNeeded(in: context)
        // 用户已读部分书：改一本的位置字段，再 seed 不应清空
        let books = try context.fetch(FetchDescriptor<Book>())
        let first = try #require(books.first)
        first.currentLocation = "1:20"
        first.readingProgress = 0.42
        try context.save()

        try SeedData.seedIfNeeded(in: context)

        let after = try context.fetch(FetchDescriptor<Book>())
        let same = try #require(after.first { $0.id == first.id })
        #expect(same.currentLocation == "1:20")
        #expect(same.readingProgress == 0.42)
    }

    @Test func seedIsIdempotentAcrossLaunches() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        try SeedData.seedIfNeeded(in: context)
        let firstBookCount = try context.fetchCount(FetchDescriptor<Book>())
        #expect(firstBookCount == 1)

        // 第二次调用（模拟再次启动）不得重复插入
        try SeedData.seedIfNeeded(in: context)
        let secondBookCount = try context.fetchCount(FetchDescriptor<Book>())
        #expect(secondBookCount == firstBookCount)
    }

    @Test func seedWritesAudioMetadataFromCatalog() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        try SeedData.seedIfNeeded(in: container.mainContext)
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        let book = try #require(books.first)
        #expect(book.audioFileName == "jiangshu.mp3")
        #expect(book.hasAudio == true)

        let catalog = try InitialLibraryLoader.load()
        let initial = try #require(catalog.books.first)
        #expect(initial.audio?.file == "jiangshu.mp3")
        #expect(initial.audio?.durationMinutes == 50)
    }

    // MARK: - Bundle 资源存在性（防漏打包）

    @Test func catalogAudioFileExistsInBundle() throws {
        let catalog = try InitialLibraryLoader.load()
        for book in catalog.books {
            guard let audio = book.audio else { continue }
            let url = Bundle.main.url(
                forResource: audio.file,
                withExtension: nil,
                subdirectory: "Books/\(book.id)"
            )
            #expect(url != nil, "catalog 登记的音频文件必须在 bundle 中: \(book.id)/\(audio.file)")
        }
    }

    // MARK: - Stale book cleanup

    @Test func staleCuratedBookWithMissingSourceIsRemoved() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let stale = Book(title: "Stale Curated", author: "Old Author", format: .epub)
        stale.sourceFileName = "old-removed-book"
        stale.catalogID = "old-removed-book"
        context.insert(stale)
        try context.save()

        try SeedData.cleanupStaleBooks(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.isEmpty)
    }

    @Test func importedBookWithMissingSourceIsRemoved() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let imported = Book(title: "Lost Import", author: "User", format: .epub)
        imported.sourceFileName = "missing-uuid"
        context.insert(imported)
        try context.save()

        try SeedData.cleanupStaleBooks(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.isEmpty)
    }

    @Test func importedBookWithExistingSourceIsKept() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let sourceName = "kept-uuid"
        let bookDir = BookSourceResolver.directoryURL(forSourceFileName: sourceName)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bookDir) }

        let imported = Book(title: "Kept Import", author: "User", format: .epub)
        imported.sourceFileName = sourceName
        context.insert(imported)
        try context.save()

        try SeedData.cleanupStaleBooks(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.sourceFileName == sourceName)
    }

    @Test func currentCatalogBookWithoutSourceIsKept() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let catalog = try InitialLibraryLoader.load()
        let validID = try #require(catalog.books.first?.id)

        let curated = Book(title: "Curated", author: "Author", format: .epub)
        curated.sourceFileName = validID
        curated.catalogID = validID
        context.insert(curated)
        try context.save()

        try SeedData.cleanupStaleBooks(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.catalogID == validID)
    }
}
