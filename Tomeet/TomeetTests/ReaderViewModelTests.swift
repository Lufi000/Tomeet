import Foundation
import Testing
@testable import Tomeet

struct ReaderViewModelTests {
    /// 在临时目录构造一个已解压 EPUB fixture，供 VM 解析/分页。
    @MainActor
    private func makeFixtureViewModel(book: Book, pageSize: CGSize = CGSize(width: 390, height: 700)) throws -> (ReaderViewModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReaderVM-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        try container.write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)

        let longParagraph = String(repeating: "Text enough to page. ", count: 80)
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">test</dc:identifier>
            <dc:title>VM Sample</dc:title>
            <dc:creator>A</dc:creator>
            <dc:language>en</dc:language>
          </metadata>
          <manifest>
            <item id="c0" href="c0.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="c0"/><itemref idref="c1"/></spine>
        </package>
        """
        try opf.write(to: root.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        let c0 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>One</title></head>
        <body><h1>One</h1><p>\(longParagraph)</p></body>
        </html>
        """
        try c0.write(to: root.appendingPathComponent("c0.xhtml"), atomically: true, encoding: .utf8)

        let c1 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Two</title></head>
        <body><h1>Two</h1><p>\(longParagraph)</p></body>
        </html>
        """
        try c1.write(to: root.appendingPathComponent("c1.xhtml"), atomically: true, encoding: .utf8)

        return (ReaderViewModel(book: book, provider: { _ in root }), root)
    }

    @MainActor
    @Test func loadsToReadyWithRestoredLocation() async throws {
        let book = Book(title: "VM Sample", author: "A", format: .epub)
        book.sourceFileName = "fixture"
        book.currentLocation = ReaderLocation(chapterIndex: 1, charOffset: 0).encoded
        let (viewModel, _) = try makeFixtureViewModel(book: book)
        await viewModel.loadBook(pageSize: CGSize(width: 390, height: 700))
        // 后台解析完成（Task.detached .value 回收后 phase 应更新）
        for _ in 0..<100 where viewModel.phase == .loading {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(viewModel.phase == .ready)
        #expect(viewModel.totalPages > 0)
        #expect(viewModel.currentGlobalIndex > 0, "恢复位置在第 2 章，不应落在第 0 页")
    }

    @MainActor
    @Test func missingSourceFailsWithMessage() async {
        let book = Book(title: "No Source", author: "A", format: .epub)
        book.sourceFileName = "nonexistent"
        let viewModel = ReaderViewModel(book: book, provider: { _ in nil })
        await viewModel.loadBook(pageSize: CGSize(width: 390, height: 700))
        #expect(viewModel.phase == .failed("Book source not found: nonexistent"))
    }

    @MainActor
    @Test func settlePersistsLocationAndProgress() async throws {
        let book = Book(title: "VM Sample", author: "A", format: .epub)
        book.sourceFileName = "fixture"
        let (viewModel, _) = try makeFixtureViewModel(book: book)
        await viewModel.loadBook(pageSize: CGSize(width: 390, height: 700))
        var waited = 0
        while viewModel.phase != .ready && waited < 100 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 1
        }
        try #require(viewModel.phase == .ready)
        let index = min(viewModel.totalPages - 1, 2)
        viewModel.settle(globalIndex: index)
        #expect(book.currentLocation != nil)
        #expect(book.lastOpenedDate != nil)
        if let currentLocation = book.currentLocation {
            let location = try #require(ReaderLocation(encoded: currentLocation))
            #expect(location.chapterIndex >= 0)
        }
        #expect(book.readingProgress > 0 && book.readingProgress <= 1)
    }
}
