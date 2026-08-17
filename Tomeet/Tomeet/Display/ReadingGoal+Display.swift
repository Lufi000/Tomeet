import Foundation

extension ReadingGoal {
    /// Gauge 取值 0...1：今日已读秒数 / 目标分钟*60，钳到 1。
    var todayProgress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(1, Double(todayReadingSeconds) / Double(dailyGoalMinutes * 60))
    }

    /// 中心显示如 `1:11`（mvp.md §2.3）。
    var todayTimeText: String {
        Self.clockString(seconds: todayReadingSeconds)
    }

    static func clockString(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 底部描述，如 `of your 5-minute goal`。
    var goalText: String {
        "of your \(dailyGoalMinutes)-minute goal"
    }
}