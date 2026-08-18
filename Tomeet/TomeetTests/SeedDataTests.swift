import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct SeedDataTests {
    @Test func fixtureHasFourRealBooks() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        try SeedData.seedIfNeeded(in: container.mainContext)
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        #expect(books.count == 4)
        let bySource = Dictionary(uniqueKeysWithValues: books.compactMap { book in
            book.sourceFileName.map { ($0, book) }
        })
        #expect(bySource.count == 4)
        let english = try #require(bySource["george-macdonald_if-i-had-a-father"])
        #expect(english.title == "If I Had a Father")
        #expect(english.coverImageName == "cover-1")
        #expect(english.format == .epub)
        let poor = try #require(bySource["贫穷的本质：我们为什么摆脱不了贫穷·修订版（重新理解贫穷，探究穷人之所以贫穷的根源。）"])
        #expect(poor.title == "贫穷的本质：我们为什么摆脱不了贫穷·修订版（重新理解贫穷，探究穷人之所以贫穷的根源。）")
        #expect(poor.coverImageName == "cover-2")
        let read = try #require(bySource["读懂一本书：樊登读书法"])
        #expect(read.title == "读懂一本书：樊登读书法")
        #expect(read.coverImageName == "cover-3")
        let brain = try #require(bySource["如何科学开发孩子的大脑：智商与情商发展指南"])
        #expect(brain.title == "如何科学开发孩子的大脑：智商与情商发展指南")
        #expect(brain.coverImageName == "cover-4")
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
        #expect(books.count == 4)
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
        let firstGoalCount = try context.fetchCount(FetchDescriptor<ReadingGoal>())
        #expect(firstBookCount == 4)
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
