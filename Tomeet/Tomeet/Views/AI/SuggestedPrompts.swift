import Foundation

/// 对话页首次进入的预设问题:优先用书在 catalog 里的 discussionQuestions,
/// 否则给三条通用问题。
enum SuggestedPrompts {
    static func prompts(for book: Book) -> [String] {
        if let catalogID = book.catalogID,
           let catalog = try? InitialLibraryLoader.load(),
           let initial = InitialLibraryLoader.book(for: catalogID, in: catalog),
           let questions = initial.discussionQuestions, !questions.isEmpty {
            return Array(questions.prefix(3))
        }
        return ["这本书讲了什么？", "介绍一下作者", "这本书能给我什么启发？"]
    }
}
