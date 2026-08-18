import Foundation
import Testing
@testable import Tomeet

struct ReaderIntegrationTests {
    /// 测试 host app bundle 里构建阶段解压出的 Books/ 目录。
    private var booksRoot: URL? {
        Bundle.main.url(forResource: "Books", withExtension: nil)
    }

    @Test func realFourBooksParseAndPaginate() throws {
        let root = try #require(booksRoot, "需要在 Xcode 里先 Build（触发 ditto）再 Test")
        let names = [
            "george-macdonald_if-i-had-a-father",
            "贫穷的本质：我们为什么摆脱不了贫穷",
            "读懂一本书：樊登读书法",
            "如何科学开发孩子的大脑：智商与情商发展指南",
        ]
        let context = PaginationContext(pageSize: CGSize(width: 390, height: 700))
        for name in names {
            let dir = root.appendingPathComponent(name)
            let document = try EPUBParser.parseBook(at: dir)
            #expect(document.chapters.count > 0, "\(name) 应含章节")
            let lang = document.language ?? ""
            #expect(lang.hasPrefix("en") || lang.hasPrefix("zh"),
                    "\(name) 语言应为 en/zh，实际 \(lang)")
            let pages = ChapterPager.paginate(book: document, context: context)
            #expect(pages.count == document.chapters.count, "每章恰好一段分页结果（章节不跨页）")
            for chapter in pages {
                #expect(chapter.pages.count > 0, "\(name) 每章至少一页")
                #expect(chapter.pages.allSatisfy { $0.characterRange.length > 0 })
            }
        }
    }
}
