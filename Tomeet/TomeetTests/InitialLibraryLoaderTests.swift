import Foundation
import Testing
@testable import Tomeet

struct InitialLibraryLoaderTests {
    /// 验证 bundled JSON 能解码为 1 本书、2 个主题，且每本书都有主题。
    @Test func bundledCatalogDecodes() throws {
        let catalog = try InitialLibraryLoader.load()
        #expect(catalog.books.count == 1)
        #expect(catalog.themes.count == 2)
        #expect(catalog.books.allSatisfy { !$0.themes.isEmpty })
        #expect(catalog.books.allSatisfy { $0.sourceHint.gutenberg != nil })
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
}
