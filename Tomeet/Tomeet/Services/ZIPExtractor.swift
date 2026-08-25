import Foundation
import ZIPFoundation

/// ZIP 解压的薄封装，方便后续替换底层实现。
enum ZIPExtractor {
    /// 将 `source` 指向的 ZIP 文件解压到 `destination` 目录。
    ///
    /// - Parameters:
    ///   - source: ZIP 文件 URL。
    ///   - destination: 目标目录 URL，必须已存在或其父目录已存在。
    static nonisolated func extract(from source: URL, to destination: URL) throws {
        try FileManager.default.unzipItem(at: source, to: destination, skipCRC32: false)
    }
}
