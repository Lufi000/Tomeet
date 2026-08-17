import Foundation
import SwiftData

@Model
final class ReadingGoal {
    var dailyGoalMinutes: Int
    var todayReadingSeconds: Int
    var currentStreak: Int
    var yearFinishedCount: Int
    var lastReadDate: Date?

    init(
        dailyGoalMinutes: Int = 5,
        todayReadingSeconds: Int = 0,
        currentStreak: Int = 0,
        yearFinishedCount: Int = 0,
        lastReadDate: Date? = nil
    ) {
        self.dailyGoalMinutes = dailyGoalMinutes
        self.todayReadingSeconds = todayReadingSeconds
        self.currentStreak = currentStreak
        self.yearFinishedCount = yearFinishedCount
        self.lastReadDate = lastReadDate
    }
}