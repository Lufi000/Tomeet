import Foundation
import Testing
@testable import Tomeet

struct SuggestedPromptsTests {
    @Test func catalogDiscussionQuestionsArePreferred() throws {
        let catalog = try InitialLibraryLoader.load()
        let initial = try #require(catalog.books.first { $0.discussionQuestions?.isEmpty == false })
        let book = Book(title: initial.title, author: initial.author, format: .epub)
        book.catalogID = initial.id

        let prompts = SuggestedPrompts.prompts(for: book)

        #expect(prompts.count <= 3)
        #expect(prompts.first == initial.discussionQuestions?.first)
    }

    @Test func fallbackPromptsForBookWithoutCatalogEntry() {
        let book = Book(title: "导入的书", author: "某人", format: .epub)

        let prompts = SuggestedPrompts.prompts(for: book)

        #expect(prompts == ["这本书讲了什么？", "介绍一下作者", "这本书能给我什么启发？"])
    }
}
