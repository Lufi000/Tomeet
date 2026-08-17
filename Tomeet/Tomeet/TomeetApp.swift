import SwiftUI
import SwiftData
import Foundation

@main
struct TomeetApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.make(isStoredInMemoryOnly: false)
            // 首次启动幂等写入 seed（mvp.md §0.1 / §2.3）
            try SeedData.seedIfNeeded(in: modelContainer.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
