import Foundation
import SwiftData

/// 幂等种子数据：从 InitialLibrary.json 加载 curated 公版书。
/// 旧假书特征（Book 非空且无任何 sourceFileName）触发重建。
enum SeedData {
    static func makeBooks(from catalog: InitialLibraryCatalog) -> [Book] {
        catalog.books.map { initialBook in
            let book = Book(
                title: initialBook.title,
                author: initialBook.author,
                format: .epub
            )
            // EPUB 文件名与 JSON 中的书籍 id 一致（见 scripts/download-initial-library.py）。
            book.sourceFileName = initialBook.id
            book.themes = initialBook.themes
            book.catalogID = initialBook.id
            book.isDownloaded = true
            return book
        }
    }

    /// 首次启动（持仓为空）时幂等写入 seed。
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
                try seedBooks(in: modelContext)
                return
            }
        }

        if bookCount == 0 {
            try seedBooks(in: modelContext)
        }
    }

    /// 清理书源已不存在的书籍：旧 catalog 删除后遗留的 curated 书、以及用户导入后被移除的书。
    /// 当前 catalog 中的书籍即使暂时缺少书源也保留，避免误删可重新下载的 curated 内容。
    static func cleanupStaleBooks(in modelContext: ModelContext) throws {
        let catalog = try InitialLibraryLoader.load()
        let validCatalogIDs = Set(catalog.books.map(\.id))

        let books = try modelContext.fetch(FetchDescriptor<Book>())
        for book in books {
            if let catalogID = book.catalogID, validCatalogIDs.contains(catalogID) {
                continue
            }
            if !BookSourceResolver.sourceExists(for: book) {
                modelContext.delete(book)
            }
        }
        try modelContext.save()
    }

    private static func seedBooks(in modelContext: ModelContext) throws {
        let catalog = try InitialLibraryLoader.load()
        for book in makeBooks(from: catalog) {
            modelContext.insert(book)
        }
        try modelContext.save()
    }
}
