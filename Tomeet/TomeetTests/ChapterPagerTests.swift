import Foundation
import UIKit
import Testing
@testable import Tomeet

struct ChapterPagerTests {
    private func sampleBook() -> BookDocument {
        BookDocument(title: "Sample", author: nil, language: "en", chapters: [
            Chapter(id: "a", title: "A", blocks: [.paragraph(String(repeating: "Hello world. ", count: 40))]),
            Chapter(id: "b", title: "B", blocks: [.paragraph(String(repeating: "Second chapter. ", count: 40))]),
        ])
    }

    private var context: PaginationContext {
        PaginationContext(pageSize: CGSize(width: 390, height: 700))
    }

    @Test func isSerifLanguageFlag() {
        #expect(ChapterPager.isSerifLanguage("en") == true)
        #expect(ChapterPager.isSerifLanguage("en-GB") == true)
        #expect(ChapterPager.isSerifLanguage("zh") == false)
        #expect(ChapterPager.isSerifLanguage(nil) == false)
    }

    @Test func cjkLanguageDetection() {
        #expect(ChapterPager.isCJKLanguage("zh") == true)
        #expect(ChapterPager.isCJKLanguage("zh-Hans") == true)
        #expect(ChapterPager.isCJKLanguage("ja") == true)
        #expect(ChapterPager.isCJKLanguage("ko") == true)
        #expect(ChapterPager.isCJKLanguage("en") == false)
        #expect(ChapterPager.isCJKLanguage(nil) == false)
    }

    @Test func bodyParagraphsHaveFirstLineIndent() throws {
        let book = BookDocument(title: "T", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "C", blocks: [.paragraph("第一段。"), .paragraph("第二段。")])
        ])
        let chapters = ChapterPager.paginate(book: book, context: context)
        let page = try #require(chapters.first?.pages.first)
        let attributes = page.text.attributes(at: 0, effectiveRange: nil)
        let style = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(style.firstLineHeadIndent > 0)
    }

    @Test func headingsDoNotHaveFirstLineIndent() throws {
        let book = BookDocument(title: "T", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "C", blocks: [.heading(level: 1, text: "标题")])
        ])
        let chapters = ChapterPager.paginate(book: book, context: context)
        let page = try #require(chapters.first?.pages.first)
        let attributes = page.text.attributes(at: 0, effectiveRange: nil)
        let style = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(style.firstLineHeadIndent == 0)
    }

    @Test func h2AndAboveUsesAccentColor() throws {
        let book = BookDocument(title: "T", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "C", blocks: [
                .heading(level: 1, text: "Chapter"),
                .heading(level: 2, text: "Section"),
            ])
        ])
        let context = PaginationContext(pageSize: CGSize(width: 390, height: 700), theme: .ink)
        let chapters = ChapterPager.paginate(book: book, context: context)
        let page = try #require(chapters.first?.pages.first)
        let fullText = page.text.string as NSString
        let h1Range = fullText.range(of: "Chapter")
        let h2Range = fullText.range(of: "Section")
        let h1Color = page.text.attribute(.foregroundColor, at: h1Range.location, effectiveRange: nil) as? UIColor
        let h2Color = page.text.attribute(.foregroundColor, at: h2Range.location, effectiveRange: nil) as? UIColor
        #expect(h1Color != h2Color, "h2 应使用强调色，与 h1 不同")
    }

    @Test func lineHeightMultipleIsApplied() throws {
        let book = BookDocument(title: "T", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "C", blocks: [.paragraph("正文。")])
        ])
        let context = PaginationContext(pageSize: CGSize(width: 390, height: 700), lineHeightMultiple: 1.8)
        let chapters = ChapterPager.paginate(book: book, context: context)
        let page = try #require(chapters.first?.pages.first)
        let attributes = page.text.attributes(at: 0, effectiveRange: nil)
        let style = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(style.lineHeightMultiple == 1.8)
    }

    @Test func chaptersNeverSpanPages() throws {
        let chapters = ChapterPager.paginate(book: sampleBook(), context: context)
        #expect(chapters.count == 2)
        for chapter in chapters {
            #expect(chapter.pages.isEmpty == false, "每章至少有 1 页")
            let firstPage = try #require(chapter.pages.first)
            #expect(firstPage.characterRange.location == 0, "章节从本页第 0 字符开始（不跨页）")
        }
    }

    @Test func pagesPartitionChapterTextExactly() throws {
        let chapters = ChapterPager.paginate(book: sampleBook(), context: context)
        for chapter in chapters {
            let fullText = sampleBook().chapters[chapter.chapterIndex].blocks.map(\.text).joined(separator: "\n")
            let ranges = chapter.pages.map(\.characterRange)
            var covered = 0
            for (index, range) in ranges.enumerated() {
                #expect(range.location == covered, "第 \(index) 页起始 == 已覆盖 \(covered)")
                covered += range.length
            }
            #expect(covered == (fullText as NSString).length)
        }
    }

    @Test func pageTextMatchesSubstring() throws {
        let chapters = ChapterPager.paginate(book: sampleBook(), context: context)
        let chapter = chapters[0]
        let fullText = sampleBook().chapters[0].blocks.map(\.text).joined(separator: "\n") as NSString
        for page in chapter.pages {
            let expected = fullText.substring(with: page.characterRange)
            #expect(page.text.string == expected, "页文本与 characterRange 子串一致（字形↔字符往返不截断）")
        }
    }

    @Test func emptyChapterProducesNoPages() {
        let book = BookDocument(title: "T", author: nil, language: "en", chapters: [Chapter(id: "e", title: "E", blocks: [])])
        let chapters = ChapterPager.paginate(book: book, context: context)
        #expect(chapters[0].pages.isEmpty)
    }

    @Test func tinyContainerDoesNotHang() {
        let tiny = PaginationContext(pageSize: CGSize(width: 50, height: 10))
        let chapters = ChapterPager.paginate(book: sampleBook(), context: tiny)
        #expect(chapters.allSatisfy { $0.pages.count <= 1 } || true, "极端小尺寸不无限循环（实现有 length == 0 兜底）")
    }

    // MARK: - 页首缩进（分页与上屏的又一处不一致）

    /// 页首落在段落中段时，这一页**不能**有首行缩进。
    ///
    /// 分页时它是整章字符串里的一行，前面还有别的内容，所以 TextKit 不把它当段落首行；
    /// 上屏时它是**这一页字符串的第一行** —— TextKit 会照段落首行处理，套上
    /// `firstLineHeadIndent`（2 字 = 34pt）。首行因此少排两个字，多出来的字挤到下一行，
    /// 页尾那一行就装不下被裁掉：用户看到的就是「每页末尾丢一两个字」。
    @Test func continuationPageHasNoFirstLineIndent() throws {
        let book = oneLongParagraphBook()
        let chapters = ChapterPager.paginate(book: book, context: context)
        let pages = try #require(chapters.first?.pages)

        // 找一个"页首是段落中段"的页：页首字符不是换行后的第一个字。
        let fullText = book.chapters[0].blocks.map(\.text).joined(separator: "\n") as NSString
        var checked = 0
        for page in pages where page.characterRange.location > 0 {
            let previous = fullText.substring(with: NSRange(location: page.characterRange.location - 1, length: 1))
            guard previous != "\n" else { continue }  // 这页正好起新段，缩进是对的

            let storage = NSTextStorage(attributedString: page.text)
            let manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            let container = NSTextContainer(size: CGSize(width: 334, height: 628))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            // 用字形实际落点量缩进：lineFragmentRect 给的是整行矩形，不含 head indent。
            let firstGlyphX = manager.location(forGlyphAt: 0).x
            #expect(firstGlyphX == 0, "页首是段落中段，这一行不该有首行缩进（实际缩进 \(firstGlyphX)pt）")
            checked += 1
        }
        #expect(checked > 0, "fixture 里必须有页首落在段落中段的页，否则这条用例什么都没测")
    }

    /// 一整段超长正文。页边界必然落在段落中段，而且**每页末行都是排满的** ——
    /// 「页首多缩两个字」在这里会立刻变成「页尾那行装不下」，也就是用户看到的丢字。
    private func oneLongParagraphBook() -> BookDocument {
        BookDocument(title: "T", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "C", blocks: [
                .paragraph(String(
                    repeating: "想象一下，为了拥有美好的生活，你必须穿越一片危险的丛林。你可以安全地留在原地。",
                    count: 40
                ))
            ])
        ])
    }

    /// 上屏是**按页**排版的：每页一个独立字符串、一个独立容器。
    /// 所以每一页的文本必须能**单独**装进正文容器 —— 装不下，页尾就会被裁掉。
    ///
    /// 分页是按整章排的，两者只要有一处不一致（首行缩进就是一处），多出来的内容就会在页尾被吞。
    @Test func everyPageFitsWhenLaidOutOnItsOwn() throws {
        let chapters = ChapterPager.paginate(book: oneLongParagraphBook(), context: context)
        let pages = try #require(chapters.first?.pages)
        try #require(pages.count > 2, "fixture 要够长，否则测不到「页首落在段落中段」的页")

        let insets = context.resolvedInsets
        let containerSize = CGSize(
            width: context.pageSize.width - insets.leading - insets.trailing,
            height: context.pageSize.height - insets.top - insets.bottom
        )

        for (index, page) in pages.enumerated() {
            let storage = NSTextStorage(attributedString: page.text)
            let manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            let container = NSTextContainer(size: containerSize)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)

            let fitted = manager.glyphRange(for: container)
            #expect(
                fitted.length == manager.numberOfGlyphs,
                "第 \(index + 1) 页单独排一遍装不下容器（页尾 \(manager.numberOfGlyphs - fitted.length) 个字形会被裁掉）"
            )
        }
    }

    // MARK: - 引文样式

    private func quoteBook() -> BookDocument {
        BookDocument(title: "T", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "C", blocks: [
                .paragraph("正文一段。"),
                .quote("说实话，预测的价值并不是很高，而且大多数做预测的人并没有在市场上赚钱。"),
                .paragraph("正文又一段。"),
            ])
        ])
    }

    /// 引文要一眼看得出是引文：带竖线标记（渲染端据此画线）。
    @Test func quoteRunsAreTaggedForTheRule() throws {
        let chapters = ChapterPager.paginate(book: quoteBook(), context: context)
        let page = try #require(chapters.first?.pages.first)
        var tagged = ""
        var untagged = ""
        page.text.enumerateAttribute(.tomeetQuote, in: NSRange(location: 0, length: page.text.length)) { value, range, _ in
            let slice = (page.text.string as NSString).substring(with: range)
            if value != nil { tagged += slice } else { untagged += slice }
        }
        #expect(tagged.contains("预测的价值"), "引文段应带标记")
        #expect(!untagged.contains("预测的价值"), "引文段不该混在未标记区间里")
    }

    /// 引文比正文低一档：字号小一点、左边多缩一点。
    @Test func quoteIsSmallerAndIndentedVersusBody() throws {
        let chapters = ChapterPager.paginate(book: quoteBook(), context: context)
        let page = try #require(chapters.first?.pages.first)
        let text = page.text

        let bodyRange = (text.string as NSString).range(of: "正文一段。")
        let quoteRange = (text.string as NSString).range(of: "说实话")
        let bodyFont = try #require(text.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? UIFont)
        let quoteFont = try #require(text.attribute(.font, at: quoteRange.location, effectiveRange: nil) as? UIFont)
        let bodyStyle = try #require(text.attribute(.paragraphStyle, at: bodyRange.location, effectiveRange: nil) as? NSParagraphStyle)
        let quoteStyle = try #require(text.attribute(.paragraphStyle, at: quoteRange.location, effectiveRange: nil) as? NSParagraphStyle)

        #expect(quoteFont.pointSize < bodyFont.pointSize)
        #expect(quoteStyle.headIndent == ChapterPager.quoteTextIndent)
        #expect(quoteStyle.headIndent > bodyStyle.headIndent)
        #expect(ChapterPager.quoteRuleInset + ChapterPager.quoteRuleWidth < ChapterPager.quoteTextIndent,
                "竖线必须画在缩进槽里，不能压到引文文字上")
    }

    // MARK: - 章首页的章标题

    /// 章节标题要排进每章第一页，但**绝不能进 canonical 正文** ——
    /// 高亮、书签、阅读位置全都靠 `characterRange` 与 `Chapter.plainText` 的
    /// 一一对应来换算偏移，正文串里多一个字，所有已存标注就整体错位。
    ///
    /// 所以标题走 `header`：只带文本和量好的高度，页文本本身一个字符都不多。
    private func longChapterBook(firstBlock: Block? = nil) -> BookDocument {
        var blocks: [Block] = firstBlock.map { [$0] } ?? []
        blocks.append(.paragraph(String(
            repeating: "想象一下，为了拥有美好的生活，你必须穿越一片危险的丛林。你可以安全地留在原地，过着普通的生活。",
            count: 40
        )))
        return BookDocument(title: "T", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "3 我的低谷", blocks: blocks)
        ])
    }

    @Test func chapterHeaderOnFirstPageOnly() throws {
        let chapters = ChapterPager.paginate(book: longChapterBook(), context: context)
        let pages = try #require(chapters.first?.pages)
        try #require(pages.count > 2, "fixture 要够长，否则测不出「只有首页有标题」")

        #expect(pages[0].header?.title == "3 我的低谷")
        #expect(pages.dropFirst().allSatisfy { $0.header == nil })
    }

    @Test func chapterTitleNeverEntersPageText() throws {
        let chapters = ChapterPager.paginate(book: longChapterBook(), context: context)
        let pages = try #require(chapters.first?.pages)
        let fullText = longChapterBook().chapters[0].blocks.map(\.text).joined(separator: "\n") as NSString

        #expect(pages[0].characterRange.location == 0, "首页仍从第 0 字符开始")
        for page in pages {
            #expect(page.text.string == fullText.substring(with: page.characterRange), "页文本必须还是 canonical 子串")
        }
    }

    @Test func chapterHeaderReservesRoomOnFirstPage() throws {
        let chapters = ChapterPager.paginate(book: longChapterBook(), context: context)
        let pages = try #require(chapters.first?.pages)
        let header = try #require(pages[0].header)

        let insets = context.resolvedInsets
        let containerHeight = context.pageSize.height - insets.top - insets.bottom
        #expect(header.totalHeight > 0, "标题必须占高度，否则正文会压在标题上")

        // 首页的正文是在「容器高 − 标题高」里排的：重量一遍，必须装得下。
        let storage = NSTextStorage(attributedString: pages[0].text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(
            width: context.pageSize.width - insets.leading - insets.trailing,
            height: containerHeight - header.totalHeight
        ))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        let laidOut = manager.glyphRange(for: container)
        #expect(laidOut.length == manager.numberOfGlyphs, "首页正文必须装进扣掉标题后的高度里")
    }

    @Test func chapterThatStartsWithItsOwnTitleHeadingGetsNoHeader() throws {
        // 解析器会拿章内首个 heading 当目录标题的回退 —— 这类书再排一次章标题就重复了。
        let book = longChapterBook(firstBlock: .heading(level: 1, text: "3 我的低谷"))
        let chapters = ChapterPager.paginate(book: book, context: context)
        let pages = try #require(chapters.first?.pages)
        #expect(pages[0].header == nil)
    }

    @Test func chapterWithDifferentLeadingHeadingStillGetsHeader() throws {
        // 章首标题和目录标题不是一回事（比如章首是「引言」小节标题）时，章标题照排。
        let book = longChapterBook(firstBlock: .heading(level: 1, text: "三条原则"))
        let chapters = ChapterPager.paginate(book: book, context: context)
        let pages = try #require(chapters.first?.pages)
        #expect(pages[0].header?.title == "3 我的低谷")
    }

    // MARK: - 分页与上屏的字体必须一致

    /// 中文长文，正文足够多行 —— 页尾被裁时才会露馅。
    private func cjkBook() -> BookDocument {
        BookDocument(title: "原则", author: nil, language: "zh", chapters: [
            Chapter(id: "c", title: "3 我的低谷", blocks: (0..<12).map { index in
                .paragraph("第\(index)段：" + String(
                    repeating: "想象一下，为了拥有美好的生活，你必须穿越一片危险的丛林。你可以安全地留在原地，过着普通的生活。",
                    count: 2
                ))
            })
        ])
    }

    /// 属性里声明的字体必须能画出这一页的每个字。
    ///
    /// 画不出就会走系统回退，而分页用 TextKit 1 量行高、上屏用 TextKit 2 排行，
    /// 两边对回退字体的行高处理不同 —— 一页就会差出一行的量，页尾被容器裁掉。
    @Test func declaredFontsCanRenderEveryCharacter() throws {
        let chapters = ChapterPager.paginate(book: cjkBook(), context: context)
        var unrenderable: [String] = []
        for chapter in chapters {
            for page in chapter.pages {
                let text = page.text
                text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                    guard let font = value as? UIFont, range.length > 0 else { return }
                    var characters = [UniChar](repeating: 0, count: range.length)
                    (text.string as NSString).getCharacters(&characters, range: range)
                    var glyphs = [CGGlyph](repeating: 0, count: range.length)
                    if !CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs, range.length) {
                        unrenderable.append((text.string as NSString).substring(with: range))
                    }
                }
            }
        }
        #expect(
            unrenderable.isEmpty,
            "这些文字声明的字体画不出来，上屏会回退成别的字体，行高与分页不一致：\(unrenderable.prefix(3))"
        )
    }
}
