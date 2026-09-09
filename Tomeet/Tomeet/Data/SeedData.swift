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
            book.collection = initialBook.category
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

        // 存量库增量更新：catalog 新增的书插入进来（老用户升级自动获得新书）。
        try upsertCatalogBooks(in: modelContext)

        // 存量数据回填：catalog 后来新增的字段（如讲书音频、分类）同步到已种下的书。
        try backfillFromCatalog(in: modelContext)
    }

    /// 按 catalogID（老数据回退 sourceFileName，两者都与 JSON 的 id 一致）找出库里
    /// 还没有的 catalog 书并插入；已存在的书不动，避免覆盖阅读进度等用户数据。
    private static func upsertCatalogBooks(in modelContext: ModelContext) throws {
        let catalog = try InitialLibraryLoader.load()
        let existingIDs = Set(
            try modelContext.fetch(FetchDescriptor<Book>())
                .map { $0.catalogID ?? $0.sourceFileName }
                .compactMap { $0 }
        )

        var inserted = false
        for book in makeBooks(from: catalog) where book.catalogID.map({ !existingIDs.contains($0) }) ?? false {
            modelContext.insert(book)
            inserted = true
        }
        if inserted {
            try modelContext.save()
        }
    }

    /// 按 catalogID（老数据回退 sourceFileName，两者都与 JSON 的 id 一致）对齐 catalog 里的
    /// 音频与分类信息，避免老用户升级后看不到听书入口/书库分类。
    private static func backfillFromCatalog(in modelContext: ModelContext) throws {
        let catalog = try InitialLibraryLoader.load()
        let byID = Dictionary(
            catalog.books.map { ($0.id, (audio: $0.audio?.file, category: $0.category)) },
            uniquingKeysWith: { first, _ in first }
        )

        var changed = false
        for book in try modelContext.fetch(FetchDescriptor<Book>()) {
            let catalogID = book.catalogID ?? book.sourceFileName
            guard let catalogID,
                  let entry = byID[catalogID]
            else { continue }
            if book.catalogID == nil {
                book.catalogID = catalogID
                changed = true
            }
            if book.audioFileName != entry.audio {
                book.audioFileName = entry.audio
                changed = true
            }
            if book.collection != entry.category {
                book.collection = entry.category
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
