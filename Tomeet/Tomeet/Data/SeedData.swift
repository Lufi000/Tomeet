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
            book.audioFileName = initialBook.audio?.file
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
            return
        }

        // 存量数据回填：catalog 后来新增的字段（如讲书音频）同步到已种下的书。
        try backfillFromCatalog(in: modelContext)
    }

    /// 按 catalogID（老数据回退 sourceFileName，两者都与 JSON 的 id 一致）对齐 catalog 里的
    /// 音频信息，避免老用户升级后看不到听书入口。
    private static func backfillFromCatalog(in modelContext: ModelContext) throws {
        let catalog = try InitialLibraryLoader.load()
        let audioByID = Dictionary(
            catalog.books.map { ($0.id, $0.audio?.file) },
            uniquingKeysWith: { first, _ in first }
        )

        var changed = false
        for book in try modelContext.fetch(FetchDescriptor<Book>()) {
            let catalogID = book.catalogID ?? book.sourceFileName
            guard let catalogID,
                  let audioFile = audioByID[catalogID] ?? nil
            else { continue }
            if book.catalogID == nil {
                book.catalogID = catalogID
                changed = true
            }
            if book.audioFileName != audioFile {
                book.audioFileName = audioFile
                changed = true
            }
        }
        if changed {
            try modelContext.save()
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
