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
        navPresent: Bool = false
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

    @Test func parsesEpub3LayoutWithNavigationSkipped() throws {
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
        #expect(chapter.title == "Act I")
        #expect(chapter.blocks == [
            .heading(level: 1, text: "Act I"),
            .paragraph("First line of the play."),
            .quote("Alone. (Enter NORA.)"),
        ])
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
        #expect(document.chapters.first?.title == "Fine")
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
}
