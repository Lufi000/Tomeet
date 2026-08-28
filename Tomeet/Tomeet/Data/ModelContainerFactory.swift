import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = Schema([
            Book.self,
            ReaderSettings.self,
            DailyReading.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
