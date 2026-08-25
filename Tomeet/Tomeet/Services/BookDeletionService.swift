import Foundation
import SwiftData

enum BookDeletionError: LocalizedError {
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Could not remove book: \(error.localizedDescription)"
        }
    }
}

/// 负责从 SwiftData 以及应用沙盒中移除书籍。
///
/// 注意：只会删除 `Application Support/Books` 下的导入书目录；bundle 内预置书源不会被删除。
enum BookDeletionService {
    /// 移除指定书籍：删除沙盒文件（如有）并从 modelContext 中删除对象。
    @MainActor
    static func delete(book: Book, modelContext: ModelContext) throws {
        if let sourceFileName = book.sourceFileName {
            let directoryURL = BookSourceResolver.directoryURL(forSourceFileName: sourceFileName)
            if FileManager.default.fileExists(atPath: directoryURL.path) {
                try? FileManager.default.removeItem(at: directoryURL)
            }
        }

        modelContext.delete(book)
        do {
            try modelContext.save()
        } catch {
            throw BookDeletionError.saveFailed(error)
        }
    }
}
