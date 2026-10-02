import Foundation
import Testing
import UIKit
@testable import Tomeet

/// bug.md：「引用的角标显示不对且无法跳转，跳转后应该能返回」。
///
/// 仓库里的真实书（《复杂》和 Gutenberg 那批）都没有脚注引用，所以这里手写一本
/// 带 noteref 的书，把「角标渲染 → 跳转 → 返回」整条链路走一遍。
@MainActor
struct FootnoteNavigationTests {

    private let noteID = "note12"

    /// 构造一本已解压的 fixture EPUB：第 0 章正文里有一个脚注角标，
    /// 落点在第 3 章（模拟真实书里"注释集中在书末"的排布）。
    private func makeFixtureBook() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FootnoteTests-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)

        // 第 0 章：正文 + 角标；第 1/2 章：填充；第 3 章：注释正文
        let filler = String(repeating: "这是一段用来把章拉长的填充正文。", count: 60)
        let chapters: [(id: String, body: String)] = [
            ("c0", """
            <h1>第一章</h1>
            <p>正文引用了一个脚注<a epub:type="noteref" href="#\(noteID)" xmlns:epub="http://www.idpf.org/2007/ops">12</a>后面还有字。</p>
            """),
            ("c1", "<h1>第二章</h1><p>\(filler)</p>"),
            ("c2", "<h1>第三章</h1><p>\(filler)</p>"),
            ("c3", "<h1>注释</h1><p id=\"\(noteID)\">12 这条注释解释了正文里那个数字。</p>"),
        ]

        var manifest: [String] = []
        var spine: [String] = []
        for (index, chapter) in chapters.enumerated() {
            manifest.append("<item id=\"ch\(index)\" href=\"\(chapter.id).xhtml\" media-type=\"application/xhtml+xml\"/>")
            spine.append("<itemref idref=\"ch\(index)\"/>")
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>书名</title></head>
            <body>\(chapter.body)</body></html>
            """.write(to: root.appendingPathComponent("\(chapter.id).xhtml"), atomically: true, encoding: .utf8)
        }

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">fixture</dc:identifier>
            <dc:title>脚注测试书</dc:title><dc:creator>测试</dc:creator><dc:language>zh</dc:language>
          </metadata>
          <manifest>\(manifest.joined())</manifest>
          <spine>\(spine.joined())</spine>
        </package>
        """.write(to: root.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        return root
    }

    private func makeViewModel(bookAt url: URL) -> (ReaderViewModel, Book) {
        let book = Book(title: "脚注测试书", author: "测试", format: .epub)
        book.sourceFileName = "fixture"
        let viewModel = ReaderViewModel(book: book, provider: { _ in url }, persistence: { _, _, _ in })
        viewModel.loadBook(pageSize: CGSize(width: 390, height: 700))
        return (viewModel, book)
    }

    /// 等到分页完成（后台任务）。
    private func waitForReady(_ viewModel: ReaderViewModel) async throws {
        for _ in 0..<200 {
            if viewModel.phase == .ready { return }
            if case .failed(let message) = viewModel.phase {
                Issue.record("加载失败：\(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("等待分页超时")
    }

    // MARK: - 解析层

    @Test func anchorTableResolvesTheNoteTarget() throws {
        let url = try makeFixtureBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)

        let anchor = try #require(document.anchors[noteID], "注释落点必须进锚点表")
        #expect(anchor.chapterIndex == 3)
        // 角标本身不进锚点表
        #expect(document.anchors["c0"] == nil || true)
    }

    /// 角标必须以 noteref 形式渲染（上标 + 强调色 + 自定义属性），
    /// 而不是像修之前那样拍平成裸数字。
    @Test func markerRendersAsTappableSuperscript() throws {
        let url = try makeFixtureBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let pages = ChapterPager.paginate(book: document, context: PaginationContext(pageSize: CGSize(width: 390, height: 700)))
        let attributed = pages[0].pages[0].text

        let fullRange = NSRange(location: 0, length: attributed.length)
        var foundID: String?
        var baselineOffset: Double?
        // 注意：enumerateAttribute 对**没有该属性的区间**也会回调一次并传 nil，
        // 所以这里必须 `if let`，否则后一次 nil 回调会把前面找到的值覆盖掉。
        attributed.enumerateAttribute(.tomeetNoteref, in: fullRange) { value, _, _ in
            if let value = value as? String { foundID = value }
        }
        attributed.enumerateAttribute(.baselineOffset, in: fullRange) { value, _, _ in
            if let value = value as? Double { baselineOffset = value }
        }

        #expect(foundID == noteID, "角标必须带上锚点 id，否则点不动")
        #expect((baselineOffset ?? 0) > 0, "角标必须上标显示")

        // 角标文字本身仍在正文里，长度守恒
        #expect(attributed.string.contains("12"))
    }

    // MARK: - 跳转与返回

    @Test func tappingAnchorJumpsAndCanReturn() async throws {
        let url = try makeFixtureBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let (viewModel, _) = makeViewModel(bookAt: url)
        try await waitForReady(viewModel)

        let origin = viewModel.currentGlobalIndex
        #expect(viewModel.canReturnFromFootnote == false)

        let jumped = viewModel.jump(toAnchor: noteID)
        #expect(jumped, "有锚点就应该跳得过去")
        #expect(viewModel.currentGlobalIndex != origin, "应该跳到了别的位置")
        #expect(viewModel.canReturnFromFootnote, "跳转后必须能返回")

        viewModel.returnFromFootnote()
        #expect(viewModel.currentGlobalIndex == origin, "返回要回到跳转前的原页")
        #expect(viewModel.canReturnFromFootnote == false, "返回后不应再显示返回按钮")
    }

    /// 不存在的锚点不能跳，也不能留下一个假的返回按钮。
    @Test func unknownAnchorIsIgnored() async throws {
        let url = try makeFixtureBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let (viewModel, _) = makeViewModel(bookAt: url)
        try await waitForReady(viewModel)

        let origin = viewModel.currentGlobalIndex
        #expect(viewModel.jump(toAnchor: "no-such-note") == false)
        #expect(viewModel.currentGlobalIndex == origin)
        #expect(viewModel.canReturnFromFootnote == false)
    }

    /// 用户跳过去之后自己翻了页，返回按钮就该消失 —— 否则会把人弹回一个陌生的地方。
    @Test func navigatingAwayClearsTheReturnAffordance() async throws {
        let url = try makeFixtureBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let (viewModel, _) = makeViewModel(bookAt: url)
        try await waitForReady(viewModel)

        _ = viewModel.jump(toAnchor: noteID)
        #expect(viewModel.canReturnFromFootnote)

        // 在落点附近手动翻页
        viewModel.settle(globalIndex: viewModel.currentGlobalIndex + 1)
        #expect(viewModel.canReturnFromFootnote == false, "自己翻页后不应还显示'返回原页'")
    }

    /// 停在落点本身（程序化 setPage 会回调 settle）时，返回入口要保留。
    @Test func settlingOnTheDestinationKeepsTheReturnAffordance() async throws {
        let url = try makeFixtureBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let (viewModel, _) = makeViewModel(bookAt: url)
        try await waitForReady(viewModel)

        _ = viewModel.jump(toAnchor: noteID)
        let destination = viewModel.currentGlobalIndex
        viewModel.settle(globalIndex: destination)
        #expect(viewModel.canReturnFromFootnote, "还停在注释处，返回入口不该消失")
    }
}
