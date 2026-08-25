import Foundation

/// 对应 `InitialLibrary.json` 的根对象。
struct InitialLibraryCatalog: Codable {
    let version: String
    let description: String
    let sourcePolicy: String
    let themes: [InitialTheme]
    let books: [InitialBook]
}

/// 对应 JSON 中的单个主题。
struct InitialTheme: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let coreQuestions: [String]
}

/// 对应 JSON 中的单本书。
struct InitialBook: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let year: Int
    let themes: [String]
    let sourceHint: SourceHint
    let qualitySignals: QualitySignals
    let discussionQuestions: [String]
}

/// 下载来源提示。
struct SourceHint: Codable {
    let standardEbooks: String?
    let gutenberg: String?
}

/// 质量信号，仅用于筛选/排序，不进入 SwiftData。
struct QualitySignals: Codable {
    let standardEbooks: Bool
    let greatBooksList: Bool
    let wikipediaLanguages: Int
    let gutenbergDownloads: Int
}

/// 负责从 App Bundle 读取并解析 `InitialLibrary.json`。
enum InitialLibraryLoader {
    enum LoadError: Error {
        case missingResource
        case decodeFailed(Error)
    }

    static let resourceName = "InitialLibrary"
    static let resourceExtension = "json"

    /// 加载 bundled catalog。失败时抛出清晰错误，便于启动时排查。
    static func load() throws -> InitialLibraryCatalog {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) else {
            throw LoadError.missingResource
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(InitialLibraryCatalog.self, from: data)
        } catch {
            throw LoadError.decodeFailed(error)
        }
    }

    /// 按 `catalogID` 查找书籍元数据。
    static func book(for catalogID: String, in catalog: InitialLibraryCatalog) -> InitialBook? {
        catalog.books.first { $0.id == catalogID }
    }

    /// 按主题 id 查找主题元数据。
    static func theme(for themeID: String, in catalog: InitialLibraryCatalog) -> InitialTheme? {
        catalog.themes.first { $0.id == themeID }
    }
}
