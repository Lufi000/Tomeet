import Foundation
import Testing
@testable import Tomeet

struct ReaderIntegrationTests {
    /// 测试 host app bundle 里构建阶段解压出的 Books/ 目录。
    private var booksRoot: URL? {
        Bundle.main.url(forResource: "Books", withExtension: nil)
    }

    @Test func catalogBooksParseAndPaginate() throws {
        let root = try #require(booksRoot, "需要在 Xcode 里先 Build（触发 ditto）再 Test")
        let catalog = try InitialLibraryLoader.load()
        let context = PaginationContext(pageSize: CGSize(width: 390, height: 700))

        var testedCount = 0
        var totalPages = 0

        for book in catalog.books {
            let dir = root.appendingPathComponent(book.id)
            guard FileManager.default.fileExists(atPath: dir.path) else {
                continue
            }

            // 跳过损坏/占位 EPUB（如下载失败的 HTML 页），只验证可解析的真书。
            guard let document = try? EPUBParser.parseBook(at: dir) else {
                continue
            }

            #expect(document.chapters.count > 0, "\(book.id) 应含章节")
            let lang = document.language ?? ""
            #expect(lang.hasPrefix("en") || lang.hasPrefix("zh"),
                    "\(book.id) 语言应为 en/zh，实际 \(lang)")
            let pages = ChapterPager.paginate(book: document, context: context)
            #expect(pages.count == document.chapters.count, "\(book.id) 每章恰好一段分页结果（章节不跨页）")
            for chapter in pages {
                totalPages += chapter.pages.count
                #expect(chapter.pages.allSatisfy { $0.characterRange.length > 0 })
            }
            testedCount += 1
        }

        #expect(testedCount > 0, "Catalog 中至少有一本书已解压并可解析")
        #expect(totalPages > 0, "已解析的书至少有一页可读内容")
    }
}
