import Foundation
import SwiftData

enum SeedData {
    /// 6 本状态各异的书：进度 / NEW / 未下载云态 / 格式全覆盖。
    static func makeBooks() -> [Book] {
        let now = Date.now
        return [
            Book(title: "The Pragmatic Programmer", author: "David Thomas & Andrew Hunt",
                 coverImageName: "cover-1", format: .epub, addedDate: now.addingTimeInterval(-86400 * 30),
                 lastOpenedDate: now.addingTimeInterval(-3600), readingProgress: 0.07),
            Book(title: "Sapiens", author: "Yuval Noah Harari",
                 coverImageName: "cover-2", format: .epub, addedDate: now.addingTimeInterval(-86400 * 20),
                 lastOpenedDate: now.addingTimeInterval(-86400), readingProgress: 0.69),
            Book(title: "A Brief History of Time", author: "Stephen Hawking",
                 coverImageName: "cover-3", format: .pdf, addedDate: now.addingTimeInterval(-86400 * 10),
                 readingProgress: 0, isNew: true, isDownloaded: false),
            Book(title: "Deep Work", author: "Cal Newport",
                 coverImageName: "cover-4", format: .epub, addedDate: now.addingTimeInterval(-86400 * 5),
                 readingProgress: 0, isNew: true),
            Book(title: "Atomic Habits", author: "James Clear",
                 coverImageName: "cover-5", format: .audiobook, addedDate: now.addingTimeInterval(-86400 * 3),
                 lastOpenedDate: now.addingTimeInterval(-7200), readingProgress: 0.35),
            Book(title: "The Design of Everyday Things", author: "Don Norman",
                 coverImageName: "cover-6", format: .epub, addedDate: now.addingTimeInterval(-86400),
                 lastOpenedDate: now.addingTimeInterval(-86400 * 2), readingProgress: 0.02),
        ]
    }

    static func makeReadingGoal() -> ReadingGoal {
        ReadingGoal(dailyGoalMinutes: 5, todayReadingSeconds: 71, currentStreak: 3, yearFinishedCount: 4, lastReadDate: .now)
    }

    /// 首次启动（持仓为空）时幂等写入 seed；已有数据则跳过。
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let bookCount = try modelContext.fetchCount(FetchDescriptor<Book>())
        let goalCount = try modelContext.fetchCount(FetchDescriptor<ReadingGoal>())
        guard bookCount == 0, goalCount == 0 else { return }

        for book in makeBooks() {
            modelContext.insert(book)
        }
        modelContext.insert(makeReadingGoal())
        try modelContext.save()
    }
}
