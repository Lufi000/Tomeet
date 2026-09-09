import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct SeedDataTests {
    @Test func fixtureSeedsEntireCatalog() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        try SeedData.seedIfNeeded(in: container.mainContext)
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())

        let catalog = try InitialLibraryLoader.load()
        #expect(books.count == catalog.books.count)
        #expect(books.allSatisfy { $0.sourceFileName != nil })
        #expect(books.allSatisfy { $0.catalogID != nil })
        #expect(books.allSatisfy { $0.format == .epub })
        // 策展主题只挂在 curated 书上，但每本书都必须有分类
        #expect(books.contains { !$0.themes.isEmpty })
    }

    @Test func legacyFakeBooksAreRebuilt() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        // 手工种入「假书特征」：Book 非空且无任何 sourceFileName
        let fake = Book(title: "旧假书", author: "某作者", format: .epub)
        context.insert(fake)
        try context.save()

        try SeedData.seedIfNeeded(in: context)

        let catalog = try InitialLibraryLoader.load()
        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == catalog.books.count)
        #expect(books.allSatisfy { $0.sourceFileName != nil })
    }

    @Test func newCatalogBooksAreUpsertedIntoExistingLibrary() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let catalog = try InitialLibraryLoader.load()
        try #require(catalog.books.count > 1)

        // 模拟老版本安装：库里只有第一版 curated 的那本书
        let first = try #require(catalog.books.first)
        let legacy = Book(title: first.title, author: first.author, format: .epub)
        legacy.sourceFileName = first.id
        legacy.catalogID = first.id
        context.insert(legacy)
        try context.save()

        try SeedData.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == catalog.books.count)
        // 幂等：再 seed 一次不得重复
        try SeedData.seedIfNeeded(in: context)
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == catalog.books.count)
        // 老书进度字段不被 upsert 覆盖
        #expect(books.first { $0.catalogID == first.id }?.id == legacy.id)
    }

    @Test func categoryFromCatalogIsWrittenToCollection() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        try SeedData.seedIfNeeded(in: container.mainContext)

        let catalog = try InitialLibraryLoader.load()
        let categorized = try #require(catalog.books.first { $0.category != nil })
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        let book = try #require(books.first { $0.catalogID == categorized.id })
        #expect(book.collection == categorized.category)
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
        let catalog = try InitialLibraryLoader.load()
        let firstBookCount = try context.fetchCount(FetchDescriptor<Book>())
        #expect(firstBookCount == catalog.books.count)

        // 第二次调用（模拟再次启动）不得重复插入
        try SeedData.seedIfNeeded(in: context)
        let secondBookCount = try context.fetchCount(FetchDescriptor<Book>())
        #expect(secondBookCount == firstBookCount)
    }

    @Test func seedWritesAudioMetadataFromCatalog() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        try SeedData.seedIfNeeded(in: container.mainContext)

        let catalog = try InitialLibraryLoader.load()
        let initial = try #require(catalog.books.first { $0.audio != nil })
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        let book = try #require(books.first { $0.catalogID == initial.id })
        #expect(book.audioFileName == "jiangshu.mp3")
        #expect(book.hasAudio == true)
        #expect(initial.audio?.file == "jiangshu.mp3")
        #expect(initial.audio?.durationMinutes == 61)
    }

    // MARK: - Bundle 资源存在性（防漏打包）

    @Test func existingBookWithoutAudioIsBackfilledFromCatalog() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        // 模拟老版本已种下的书：有 catalogID/sourceFileName，但还没有音频字段
        let catalog = try InitialLibraryLoader.load()
        let initial = try #require(catalog.books.first)
        let legacy = Book(title: initial.title, author: initial.author, format: .epub)
        legacy.sourceFileName = initial.id
        legacy.catalogID = initial.id
        context.insert(legacy)
        try context.save()

        try SeedData.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == catalog.books.count)
        let seeded = books.first { $0.id == legacy.id }
        #expect(seeded?.audioFileName == initial.audio?.file)
        #expect(seeded?.hasAudio == true)
    }

    @Test func legacyBookWithoutCatalogIDIsBackfilledViaSourceFileName() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        // 更老的数据：有 sourceFileName 但 catalogID 还没引入（nil）
        let catalog = try InitialLibraryLoader.load()
        let initial = try #require(catalog.books.first)
        let legacy = Book(title: initial.title, author: initial.author, format: .epub)
        legacy.sourceFileName = initial.id
        context.insert(legacy)
        try context.save()

        try SeedData.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == catalog.books.count)
        let seeded = books.first { $0.id == legacy.id }
        #expect(seeded?.catalogID == initial.id)
        #expect(seeded?.audioFileName == initial.audio?.file)
        #expect(seeded?.hasAudio == true)
    }

    @Test func catalogAudioFileExistsInBundle() throws {
        let catalog = try InitialLibraryLoader.load()
        for book in catalog.books {
            guard let audio = book.audio else { continue }
            // 豁免逻辑：mp3/epub 被 gitignore，新机器/CI 首次 clone（未跑 TTS 管道）时
            // 整个 Books/<book.id> 目录都不存在，此时跳过断言（无资产环境）；
            // 一旦目录已打包进 bundle，音频缺失就必须断言失败（保留防漏打包的牙齿）。
            let bookDir = Bundle.main.url(
                forResource: book.id,
                withExtension: nil,
                subdirectory: "Books"
            )
            guard bookDir != nil else { continue }
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

    @Test func summaryFromCatalogIsSeededAndBackfilled() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        // 模拟老版本已种下的书:有 catalogID,还没有 summary 字段值
        let catalog = try InitialLibraryLoader.load()
        let initial = try #require(catalog.books.first)
        let legacy = Book(title: initial.title, author: initial.author, format: .epub)
        legacy.sourceFileName = initial.id
        legacy.catalogID = initial.id
        context.insert(legacy)
        try context.save()

        try SeedData.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        let seeded = try #require(books.first { $0.id == legacy.id })
        #expect(seeded.summary == initial.summary)
        // #expect(seeded.summary != nil)  // Task 2 恢复:JSON 暂无简介数据,Task 2 填数据后取消注释
    }
}
