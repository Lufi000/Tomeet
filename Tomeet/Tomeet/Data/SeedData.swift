import Foundation
import SwiftData

/// 幂等种子数据：4 本随包公版书 + 单个 ReadingGoal。旧假书特征（Book 非空且无任何 sourceFileName）触发重建。
enum SeedData {
    struct BookSeed {
        let title: String
        let author: String
        let sourceFileName: String
        let coverImageName: String
    }

    static let bookSeeds: [BookSeed] = [
        BookSeed(title: "If I Had a Father", author: "George MacDonald",
                 sourceFileName: "george-macdonald_if-i-had-a-father", coverImageName: "cover-1"),
        BookSeed(title: "贫穷的本质：我们为什么摆脱不了贫穷·修订版（重新理解贫穷，探究穷人之所以贫穷的根源。）", author: "阿比吉特·班纳吉",
                 sourceFileName: "贫穷的本质：我们为什么摆脱不了贫穷·修订版（重新理解贫穷，探究穷人之所以贫穷的根源。）", coverImageName: "cover-2"),
        BookSeed(title: "读懂一本书：樊登读书法", author: "樊登",
                 sourceFileName: "读懂一本书：樊登读书法", coverImageName: "cover-3"),
        BookSeed(title: "如何科学开发孩子的大脑：智商与情商发展指南", author: "吉尔·斯塔姆（Jill Stamm）",
                 sourceFileName: "如何科学开发孩子的大脑：智商与情商发展指南", coverImageName: "cover-4"),
    ]

    static func makeBooks() -> [Book] {
        bookSeeds.map { seed in
            let book = Book(title: seed.title, author: seed.author, format: .epub)
            book.sourceFileName = seed.sourceFileName
            book.coverImageName = seed.coverImageName
            book.isDownloaded = true
            return book
        }
    }

    static func makeReadingGoal() -> ReadingGoal {
        ReadingGoal(dailyGoalMinutes: 5, todayReadingSeconds: 71, currentStreak: 3, yearFinishedCount: 4, lastReadDate: .now)
    }

    /// 首次启动（持仓为空）时幂等写入 seed；已有数据时：假书特征触发重建，否则仅补 ReadingGoal。
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let bookCount = try modelContext.fetchCount(FetchDescriptor<Book>())

        // 旧数据迁移（定稿）：Book 非空但没有任何书带 sourceFileName = 假书特征 → 重建。
        if bookCount > 0 {
            let books = try modelContext.fetch(FetchDescriptor<Book>())
            let hasSource = books.contains { $0.sourceFileName != nil }
            if !hasSource {
                for book in books {
                    modelContext.delete(book)
                }
                seedBooksAndGoal(in: modelContext)
                return
            }
        }

        if bookCount == 0 {
            seedBooksAndGoal(in: modelContext)
            return
        }

        // 非空且带 sourceFileName：真书已存在，仅补 ReadingGoal（幂等）。
        let goalCount = try modelContext.fetchCount(FetchDescriptor<ReadingGoal>())
        if goalCount == 0 {
            modelContext.insert(makeReadingGoal())
            try modelContext.save()
        }
    }

    private static func seedBooksAndGoal(in modelContext: ModelContext) {
        for book in makeBooks() {
            modelContext.insert(book)
        }
        modelContext.insert(makeReadingGoal())
        try? modelContext.save()
    }
}
