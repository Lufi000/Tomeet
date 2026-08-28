import Foundation
import SwiftData

/// 某一天的阅读/听书时长（秒）。`date` 归一化到当天 0:00，一天至多一条。
@Model
final class DailyReading {
    var date: Date
    var readSeconds: TimeInterval
    var listenSeconds: TimeInterval

    init(date: Date, readSeconds: TimeInterval = 0, listenSeconds: TimeInterval = 0) {
        self.date = date
        self.readSeconds = readSeconds
        self.listenSeconds = listenSeconds
    }

    /// 按自然日累计：有当日记录则加上增量，否则新建记录。
    static func add(
        readSeconds: TimeInterval,
        listenSeconds: TimeInterval,
        on date: Date,
        to context: ModelContext
    ) throws {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyReading>(
            predicate: #Predicate { $0.date == day }
        )
        if let record = try context.fetch(descriptor).first {
            record.readSeconds += readSeconds
            record.listenSeconds += listenSeconds
        } else {
            context.insert(DailyReading(date: day, readSeconds: readSeconds, listenSeconds: listenSeconds))
        }
        try context.save()
    }
}
