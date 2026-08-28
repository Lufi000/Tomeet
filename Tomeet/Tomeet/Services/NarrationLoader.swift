import Foundation

/// 从 App Bundle 加载本地讲书 fixture。
///
/// 资源命名：`Narration_<catalogID>_<locale>.json`，与 InitialLibrary.json 同目录
/// （PBXFileSystemSynchronizedRootGroup 会自动把 JSON 拷入资源）。
enum NarrationLoader {
    enum LoadError: Error {
        case missingResource(String)
        case decodeFailed(Error)
    }

    /// 当前支持的讲书语言，顺序即语言切换器的展示顺序。
    static let supportedLocales = ["zh-Hans", "en"]

    /// 按书 + 语言加载讲书；书未收录或语言缺失时返回 nil。
    static func narration(for book: Book, locale: String) -> BookNarration? {
        guard let catalogID = book.catalogID else { return nil }
        return load(catalogID: catalogID, locale: locale)
    }

    /// 某本书可用的讲书语言列表（按 supportedLocales 顺序）。
    static func availableLocales(for book: Book) -> [String] {
        guard let catalogID = book.catalogID else { return [] }
        return supportedLocales.filter { load(catalogID: catalogID, locale: $0) != nil }
    }

    static func load(catalogID: String, locale: String) -> BookNarration? {
        let name = resourceName(catalogID: catalogID, locale: locale)
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decode(data)
    }

    static func decode(_ data: Data) throws -> BookNarration {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(BookNarration.self, from: data)
        } catch {
            throw LoadError.decodeFailed(error)
        }
    }

    static func resourceName(catalogID: String, locale: String) -> String {
        "Narration_\(catalogID)_\(locale)"
    }
}

// MARK: - 语言选择

extension NarrationLoader {
    /// 决定初始语言：已存偏好 > 系统语言 > 可用列表第一项。
    static func preferredLocale(
        available: [String],
        stored: String?,
        systemPreferred: String? = Locale.preferredLanguages.first
    ) -> String? {
        if let stored, available.contains(stored) {
            return stored
        }
        let systemLocale: String? = {
            guard let systemPreferred else { return nil }
            return systemPreferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }()
        if let systemLocale, available.contains(systemLocale) {
            return systemLocale
        }
        return available.first
    }
}
