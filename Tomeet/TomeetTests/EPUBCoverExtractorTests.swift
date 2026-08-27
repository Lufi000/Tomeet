import Foundation
import Testing
@testable import Tomeet

struct EPUBCoverExtractorTests {
    /// 使用仓库中已下载的 EPUB 验证封面能定位到有效图片文件。
    @Test func extractsCoverFromEPUB() throws {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let epubURL = repoRoot
            .appendingPathComponent("books/public_domain_books/george-macdonald_if-i-had-a-father.epub")
        let bookDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBCoverExtractorTests-\(UUID().uuidString)")

        try ZIPExtractor.extract(from: epubURL, to: bookDir)

        let coverURL = try EPUBCoverExtractor.coverURL(in: bookDir)
        let url = try #require(coverURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
