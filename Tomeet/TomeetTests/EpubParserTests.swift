import Foundation
import Testing
@testable import Tomeet

/// fixture 全部为「已解压的文本目录」，无需 zip（spec §7）。
struct EpubParserTests {
    /// 在临时目录手写一个 EPUB2 布局（OPF 在根）/ EPUB3 布局（OPF 在子目录）的 fixture。
    private func makeFixture(
        opfInSubdirectory: Bool,
        title: String,
        creator: String,
        language: String,
        chapters: [(id: String, title: String, body: String)],
        navPresent: Bool = false,
        ncxEntries: [(href: String, title: String)]? = nil
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EpubParserTests-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let opfDirURL = opfInSubdirectory ? root.appendingPathComponent("epub") : root
        try FileManager.default.createDirectory(at: opfDirURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)

        let opfPath = opfInSubdirectory ? "epub/content.opf" : "content.opf"

        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try container.write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)

        var manifest = ["""
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="style" href="style.css" media-type="text/css"/>
        """]
        var spine = [String]()
        for (index, chapter) in chapters.enumerated() {
            manifest.append("""
            <item id="ch\(index)" href="\(chapter.id).xhtml" media-type="application/xhtml+xml"/>
            """)
            spine.append("<itemref idref=\"ch\(index)\"/>")
            let xhtml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(language)">
            <head><title>\(chapter.title)</title><link rel="stylesheet" href="style.css"/></head>
            <body>
            \(chapter.body)
            </body>
            </html>
            """
            try xhtml.write(to: opfDirURL.appendingPathComponent("\(chapter.id).xhtml"), atomically: true, encoding: .utf8)
        }
        if navPresent {
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Navigation</title></head>
            <body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="ch0.xhtml">One</a></li></ol></nav></body></html>
            """.write(to: opfDirURL.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)
            manifest.append("""
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """)
        }
        if let ncxEntries {
            let navPoints = ncxEntries.enumerated().map { index, entry in
                """
                <navPoint id="np\(index)" playOrder="\(index + 1)">
                  <navLabel><text>\(entry.title)</text></navLabel>
                  <content src="\(entry.href)"/>
                </navPoint>
                """
            }.joined(separator: "\n")
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <navMap>
            \(navPoints)
              </navMap>
            </ncx>
            """.write(to: opfDirURL.appendingPathComponent("toc.ncx"), atomically: true, encoding: .utf8)
        }
        let manifestXML = manifest.joined(separator: "\n")
        let spineXML = spine.joined(separator: "\n")
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">test</dc:identifier>
            <dc:title>\(title)</dc:title>
            <dc:creator>\(creator)</dc:creator>
            <dc:language>\(language)</dc:language>
          </metadata>
          <manifest>
        \(manifestXML)
          </manifest>
          <spine toc="ncx">
        \(spineXML)
          </spine>
        </package>
        """
        try opf.write(to: opfDirURL.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func parsesEpub3LayoutAndUsesNavForTitles() throws {
        let url = try makeFixture(
            opfInSubdirectory: true,
            title: "Actors",
            creator: "Some Author",
            language: "en-GB",
            chapters: [(id: "ch0", title: "Act I", body: """
            <h1>Act I</h1><p>First line of the play.</p><blockquote><p>Alone. (Enter NORA.)</p></blockquote>
            """)],
            navPresent: true
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.title == "Actors")
        #expect(document.author == "Some Author")
        #expect(document.language == "en-GB")
        #expect(document.chapters.count == 1)
        let chapter = try #require(document.chapters.first)
        #expect(chapter.id == "ch0")
        // 标题取自 nav 目录（fixture 里是 "One"），而不是 <head><title>。
        // 这正是 bug.md「目录全是一样的书名」的修复点。
        #expect(chapter.title == "One")
        #expect(chapter.blocks == [
            .heading(level: 1, text: "Act I"),
            .paragraph("First line of the play."),
            .quote("Alone. (Enter NORA.)"),
        ])
    }

    /// 没有 nav / NCX 时，标题回退到章内首个 heading（而不是 <head><title>，那是书名）。
    @Test func titleFallsBackToFirstHeadingWithoutTOC() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "书名",
            creator: "作者",
            language: "zh",
            chapters: [(id: "ch1", title: "书名", body: "<h2>真正的章节名</h2><p>正文。</p>")]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.first?.title == "真正的章节名")
    }

    /// 既没有目录也没有 heading 时才回退到文件名。
    @Test func titleFallsBackToFileNameAsLastResort() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "书名",
            creator: "作者",
            language: "zh",
            chapters: [(id: "ch7", title: "书名", body: "<p>没有标题的正文。</p>")]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.first?.title == "ch7")
    }

    @Test func parsesEpub2RootOPFAndSkipsHeadStyle() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "贫穷的本质",
            creator: "班纳吉",
            language: "zh",
            chapters: [(id: "c1", title: "引言", body: """
            <style>p { color: red; }</style><h2>为什么要讨论贫穷</h2><p>  段落文本  with  spaces  </p>
            """)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.language == "zh")
        #expect(document.chapters.first?.blocks == [
            .heading(level: 2, text: "为什么要讨论贫穷"),
            .paragraph("段落文本 with spaces"),
        ])
    }

    @Test func skipsBrokenChapterAndKeepsOthers() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "en",
            chapters: [
                (id: "ok", title: "Fine", body: "<p>Good text</p>"),
                (id: "bad", title: "Broken", body: "unclosed <p>oops"),
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.count == 1)
        // 无目录、正文也无 heading：回退到文件名（此前会误用 <head><title>）。
        #expect(document.chapters.first?.title == "ok")
    }

    @Test func missingContainerThrows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: EPUBParser.ParseError.self) {
            _ = try EPUBParser.parseBook(at: url)
        }
    }

    @Test func emptyChapterBodyProducesNoBlocks() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "en",
            chapters: [(id: "e", title: "Empty", body: "<p></p>")]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.count == 1)
        #expect(document.chapters.first?.blocks.isEmpty == true)
    }

    // MARK: - EPUB2 NCX 目录

    @Test func epub2NCXProvidesChapterTitles() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "书名",
            creator: "作者",
            language: "zh",
            chapters: [
                (id: "c1", title: "书名", body: "<p>第一章正文</p>"),
                (id: "c2", title: "书名", body: "<p>第二章正文</p>"),
            ],
            ncxEntries: [(href: "c1.xhtml", title: "第一章 起点"), (href: "c2.xhtml", title: "第二章 混沌")]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.map(\.title) == ["第一章 起点", "第二章 混沌"])
    }

    /// NCX 的 src 可能带 fragment，要按去 fragment 后的路径匹配。
    @Test func ncxHrefWithFragmentStillMatches() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "zh",
            chapters: [(id: "c1", title: "T", body: "<p>正文</p>")],
            ncxEntries: [(href: "c1.xhtml#top", title: "带锚点的标题")]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.first?.title == "带锚点的标题")
    }

    // MARK: - 脚注角标

    /// `<a epub:type="noteref">` 不能拍平成裸数字 —— 要保留锚点，供点击跳转。
    @Test func noterefBecomesAnnotatedRun() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "zh",
            chapters: [(id: "c1", title: "T", body: """
            <p>原文<a epub:type="noteref" href="#note12" xmlns:epub="http://www.idpf.org/2007/ops">12</a>继续。</p>
            """)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let block = try #require(document.chapters.first?.blocks.first)
        #expect(block.runs.count == 3)
        #expect(block.runs[0] == InlineRun("原文"))
        #expect(block.runs[1] == InlineRun("12", noteID: "note12"))
        #expect(block.runs[2] == InlineRun("继续。"))
        // 角标文字本身仍计入正文长度 —— 高亮/阅读位置的偏移不会因标脚注而漂移。
        #expect(block.text == "原文12继续。")
    }

    /// `role="doc-noteref"` 是等价写法。
    @Test func docNoterefRoleIsAlsoRecognized() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "en",
            // 用 ##"..."## —— 内容里的 href="#n1" 含有 "#，会把单井号原始字符串提前结束
            chapters: [(id: "c1", title: "T", body: ##"<p>Text<a role="doc-noteref" href="#n1">1</a>.</p>"##)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let runs = try #require(document.chapters.first?.blocks.first?.runs)
        #expect(runs.contains { $0.noteID == "n1" })
    }

    /// 锚点表把 id 解析成章内 canonical 偏移 —— 跳转要靠它。
    @Test func anchorsResolveToChapterOffsets() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "zh",
            chapters: [(id: "c1", title: "T", body: """
            <p>第一段。</p><p id="note12">12 注释正文。</p>
            """)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let anchor = try #require(document.anchors["note12"])
        #expect(anchor.chapterIndex == 0)
        // "第一段。"(4) + 块间 "\n"(1) = 5
        #expect(anchor.charOffset == 5)
    }

    // MARK: - 插图

    @Test func imageBecomesImageBlock() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "zh",
            chapters: [(id: "c1", title: "T", body: """
            <p>前文</p><img src="images/pic.png" alt="插图"/><p>后文</p>
            """)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let blocks = try #require(document.chapters.first?.blocks)
        #expect(blocks.count == 3)
        #expect(blocks[1] == .image(ImageRef(path: "images/pic.png", alt: "插图")))
        // 图片块在正文里占一个 U+FFFC，与 NSTextAttachment 一致
        #expect(blocks[1].text == "\u{FFFC}")
    }

    /// 章节在子目录时，`<img src>` 必须相对**章节文件所在目录**解析，
    /// 而不是相对书源根目录 —— Gutenberg 的书都放在 `OEBPS/` 下，
    /// 按根目录解析会让所有图片指向不存在的路径（首页只剩一个空占位框）。
    @Test func imagePathResolvesRelativeToChapterDirectory() throws {
        let url = try makeFixture(
            opfInSubdirectory: true,   // 内容放在 epub/ 子目录
            title: "T",
            creator: "A",
            language: "en",
            chapters: [(id: "c1", title: "T", body: #"<img src="images/pic.png" alt="图"/>"#)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let block = try #require(document.chapters.first?.blocks.first)
        // 存的是相对书源根目录的路径，所以带上 epub/ 前缀
        #expect(block == .image(ImageRef(path: "epub/images/pic.png", alt: "图")))
    }

    /// 根目录布局下不加多余前缀（回归：《复杂》就是这种布局）。
    @Test func imagePathStaysFlatWhenChapterIsAtRoot() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "zh",
            chapters: [(id: "c1", title: "T", body: #"<img src="images/pic.png" alt=""/>"#)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.first?.blocks.first == .image(ImageRef(path: "images/pic.png", alt: "")))
    }

    /// 图片 href 常带百分号编码（中文文件名），要解码成真实路径。
    @Test func imagePathIsPercentDecoded() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "zh",
            chapters: [(id: "c1", title: "T", body: #"<img src="images/%E5%9B%BE.png" alt=""/>"#)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let block = try #require(document.chapters.first?.blocks.first)
        #expect(block == .image(ImageRef(path: "images/图.png", alt: "")))
    }

    @Test func imageBlockRoundTripsThroughPlainText() throws {
        let chapter = Chapter(id: "c", title: "C", blocks: [
            .paragraph("前"),
            .image(ImageRef(path: "a.png")),
            .paragraph("后"),
        ])
        // "前" + \n + U+FFFC + \n + "后" = 1+1+1+1+1 = 5
        #expect(chapter.plainText == "前\n\u{FFFC}\n后")
        #expect(chapter.textLength == 5)
    }

    // MARK: - 内联强调

    @Test func inlineEmphasisIsPreserved() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "en",
            chapters: [(id: "c1", title: "T", body: """
            <p>plain <em>slanted</em> and <strong>loud</strong> and <em><strong>both</strong></em>.</p>
            """)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        let runs = try #require(document.chapters.first?.blocks.first?.runs)
        #expect(runs.contains(InlineRun("slanted", emphasis: .italic)))
        #expect(runs.contains(InlineRun("loud", emphasis: .bold)))
        #expect(runs.contains(InlineRun("both", emphasis: .boldItalic)))
        // 强调不改变文本内容
        #expect(runs.map(\.text).joined() == "plain slanted and loud and both.")
    }
}
