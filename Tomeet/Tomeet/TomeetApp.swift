import SwiftUI
import SwiftData
import Foundation

@main
struct TomeetApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.make(isStoredInMemoryOnly: false)
            // 先清理旧 catalog/导入后书源已丢失的书籍，再 seed，避免残留空记录挡住新书写入。
            try SeedData.cleanupStaleBooks(in: modelContainer.mainContext)
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
