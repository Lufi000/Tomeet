import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct SeedDataTests {
    @Test func fixtureHasSixBooksWithStateVariety() {
        let books = SeedData.makeBooks()
        #expect(books.count >= 5)
        #expect(books.contains { $0.isNew && $0.readingProgress == 0 })
        #expect(books.contains { !$0.isDownloaded })
        #expect(books.contains { $0.readingProgress == 0.69 })
        #expect(books.contains { $0.readingProgress == 0.07 })
        #expect(books.allSatisfy { $0.collection == nil })
        // 封面命名与资产一致（cover-1…cover-6）
        for book in books {
            if let name = book.coverImageName {
                #expect(name.hasPrefix("cover-"))
            }
        }
    }

    @Test func seedIsIdempotentAcrossLaunches() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        try SeedData.seedIfNeeded(in: context)
        let firstBookCount = try context.fetchCount(FetchDescriptor<Book>())
        let firstGoalCount = try context.fetchCount(FetchDescriptor<ReadingGoal>())
        #expect(firstBookCount > 0)
        #expect(firstGoalCount == 1)

        // 第二次调用（模拟再次启动）不得重复插入
        try SeedData.seedIfNeeded(in: context)
        let secondBookCount = try context.fetchCount(FetchDescriptor<Book>())
        #expect(secondBookCount == firstBookCount)
    }

    @Test func seededReadingGoalMatchesSpecValue() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedData.seedIfNeeded(in: context)
        let goal = try context.fetch(FetchDescriptor<ReadingGoal>()).first
        #expect(goal?.dailyGoalMinutes == 5)
        #expect(goal?.todayReadingSeconds == 71) // 显示为 1:11
    }
}