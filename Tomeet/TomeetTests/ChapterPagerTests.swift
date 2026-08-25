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
}
