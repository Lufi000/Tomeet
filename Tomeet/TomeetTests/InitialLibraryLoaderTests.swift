import Foundation
import Testing
@testable import Tomeet

struct InitialLibraryLoaderTests {
    /// 验证 bundled JSON 能解码：curated 书带主题与来源提示，批量导入的书带分类。
    @Test func bundledCatalogDecodes() throws {
        let catalog = try InitialLibraryLoader.load()
        #expect(catalog.books.count > 1)
        #expect(catalog.themes.count == 2)

        let curated = catalog.books.filter { $0.sourceHint != nil }
        #expect(curated.count == 1)
        #expect(curated.allSatisfy { !$0.themes.isEmpty })
        #expect(curated.allSatisfy { $0.sourceHint?.gutenberg != nil })

        let categorized = catalog.books.filter { $0.category != nil }
        #expect(!categorized.isEmpty)
        #expect(categorized.allSatisfy { $0.sourceHint == nil })
    }

    @Test func lookupByCatalogID() throws {
        let catalog = try InitialLibraryLoader.load()
        let book = InitialLibraryLoader.book(for: "george-macdonald_if-i-had-a-father", in: catalog)
        let found = try #require(book)
        #expect(found.title == "If I Had a Father")
        #expect(found.author == "George MacDonald")
    }

    @Test func lookupByThemeID() throws {
        let catalog = try InitialLibraryLoader.load()
        let theme = InitialLibraryLoader.theme(for: "love-and-relationships", in: catalog)
        let found = try #require(theme)
        #expect(found.name == "爱与关系")
    }

    @Test func everyBookHasSummary() throws {
        let catalog = try InitialLibraryLoader.load()
        for book in catalog.books {
            let summary = try #require(book.summary, "缺少简介: \(book.id)")
            #expect(summary.count >= 20, "简介太短: \(book.id)")
        }
    }

    @Test func summaryIsOptionalInJSON() throws {
        // 不带 summary 的 JSON 片段也能解码(导入的书/旧数据兼容)
        let json = """
        {"id":"x","title":"T","author":"A","themes":[]}
        """
        let book = try JSONDecoder().decode(InitialBook.self, from: Data(json.utf8))
        #expect(book.summary == nil)
    }
}
