import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct DailyReadingTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        return container.mainContext
    }

    private func allRecords(in context: ModelContext) throws -> [DailyReading] {
        try context.fetch(FetchDescriptor<DailyReading>())
    }

    @Test func addCreatesRecordNormalizedToStartOfDay() throws {
        let context = try makeContext()
        let noon = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)

        try DailyReading.add(readSeconds: 60, listenSeconds: 30, on: noon, to: context)

        let records = try allRecords(in: context)
        #expect(records.count == 1)
        #expect(records[0].date == Calendar.current.startOfDay(for: noon))
        #expect(records[0].readSeconds == 60)
        #expect(records[0].listenSeconds == 30)
    }

    @Test func addAccumulatesOntoSameDay() throws {
        let context = try makeContext()
        let day = Calendar.current.startOfDay(for: Date())

        try DailyReading.add(readSeconds: 60, listenSeconds: 30, on: day, to: context)
        try DailyReading.add(readSeconds: 15, listenSeconds: 5, on: day.addingTimeInterval(3600), to: context)

        let records = try allRecords(in: context)
        #expect(records.count == 1)
        #expect(records[0].readSeconds == 75)
        #expect(records[0].listenSeconds == 35)
    }

    @Test func addCreatesSeparateRecordsForDifferentDays() throws {
        let context = try makeContext()
        let day1 = Calendar.current.startOfDay(for: Date())
        let day2 = day1.addingTimeInterval(86400)

        try DailyReading.add(readSeconds: 60, listenSeconds: 0, on: day1, to: context)
        try DailyReading.add(readSeconds: 0, listenSeconds: 45, on: day2, to: context)

        let records = try allRecords(in: context).sorted { $0.date < $1.date }
        #expect(records.count == 2)
        #expect(records[0].readSeconds == 60)
        #expect(records[1].listenSeconds == 45)
    }
}

// 临时探针，定位后删除
@MainActor
struct DailyReadingProbe {
    @Test func probe() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let d = DailyReading(date: Date(), readSeconds: 1, listenSeconds: 2)
        context.insert(d)
        try context.save()
        let all = try context.fetch(FetchDescriptor<DailyReading>())
        print("PROBE insert+fetch count =", all.count)
        let day = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { $0.date == day })
        let match = try context.fetch(descriptor)
        print("PROBE predicate count =", match.count)
    }
}
