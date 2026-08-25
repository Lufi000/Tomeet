import Foundation
import SwiftData

/// 统一管理导入书籍在应用沙盒中的存储路径。
///
/// 导入的书籍存放在 `~/Library/Application Support/Books/<sourceFileName>/`，
/// 其中 `<sourceFileName>` 通常使用 `Book.sourceFileName`（即导入时生成的 UUID 字符串）。
enum BookSourceResolver {
    /// `~/Library/Application Support/Books`
    static var applicationSupportBooksDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Books", isDirectory: true)
    }

    /// 返回某本导入书对应的目录 URL（无论是否存在）。
    static func directoryURL(forSourceFileName name: String) -> URL {
        applicationSupportBooksDirectory
            .appendingPathComponent(name, isDirectory: true)
    }

    /// 返回 `Book` 对应的导入书目录 URL。
    static func directoryURL(for book: Book) -> URL? {
        guard let name = book.sourceFileName else { return nil }
        return directoryURL(forSourceFileName: name)
    }

    /// 对 PDF/MOBI 等单文件格式，返回目录内的 `book.<ext>` URL。
    static func fileURL(for book: Book, extension ext: String) -> URL? {
        directoryURL(for: book)?.appendingPathComponent("book.\(ext)")
    }

    /// 检查 `Book` 对应的书源目录/文件是否存在（含 App Support 与 Bundle 回退）。
    static func sourceExists(for book: Book) -> Bool {
        guard let name = book.sourceFileName else { return false }

        let appSupportDir = directoryURL(forSourceFileName: name)
        if FileManager.default.fileExists(atPath: appSupportDir.path) {
            return true
        }

        return Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Books"
        ) != nil
    }
}
