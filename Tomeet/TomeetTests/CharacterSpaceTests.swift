import Foundation
import Testing
@testable import Tomeet

/// 字符坐标系的不变量。
///
/// 整个阅读器只认**一个**偏移坐标系：章节 `plainText` 的 UTF-16 偏移。
/// 它同时是分页结果（`NSRange`）、阅读位置（`ReaderLocation.charOffset`）和高亮锚点的基准。
/// 一旦 `ChapterPager` 渲染出的字符串长度和 `Chapter.plainText` 对不上，
/// 高亮区间、脚注跳转、阅读进度会同时整体错位 —— 而且不会有任何编译错误。
///
/// 这些断言就是防止那种静默错位。
struct CharacterSpaceTests {

    private func context(width: CGFloat = 390, height: CGFloat = 700) -> PaginationContext {
        PaginationContext(pageSize: CGSize(width: width, height: height))
    }

    private func chapter(id: String, blocks: [Block]) -> Chapter {
        Chapter(id: id, title: "T", blocks: blocks)
    }

    /// 渲染长度 == plainText 长度。这是最关键的一条。
    @Test func renderedTextLengthEqualsPlainTextLength() {
        let samples: [Chapter] = [
            chapter(id: "a", blocks: [.paragraph("abc"), .paragraph("def")]),
            chapter(id: "b", blocks: [.heading(level: 1, text: "标题"), .paragraph("正文。")]),
            chapter(id: "c", blocks: [.quote("引用"), .paragraph("段落")]),
            chapter(id: "d", blocks: []),
            chapter(id: "e", blocks: [
                .paragraph("前"),
                .image(ImageRef(path: "missing.png")),   // 图加载不出来也要占位
                .paragraph("后"),
            ]),
            // emoji 是 2 个 UTF-16 单元、1 个字符 —— 用 String.count 就会在这里错
            chapter(id: "f", blocks: [.paragraph("emoji 🙈🙉 test")]),
            chapter(id: "g", blocks: [.paragraph("混合 mixed 文本 with words")]),
        ]

        for sample in samples {
            let pages = ChapterPager.paginate(
                book: BookDocument(title: "T", author: nil, language: "zh", chapters: [sample]),
                context: context()
            )
            let rendered = pages[0].pages.reduce(0) { $0 + $1.characterRange.length }
            #expect(
                rendered == sample.textLength,
                "章节 \(sample.id)：渲染长度 \(rendered) != plainText 长度 \(sample.textLength)"
            )
        }
    }

    /// 分页结果必须**无缝铺满**整章：每页起点等于前面所有页长度之和，总长等于章长。
    @Test func pagesTileTheChapterWithoutGaps() {
        let sample = chapter(id: "x", blocks: [
            .heading(level: 1, text: "第一章"),
            .paragraph(String(repeating: "这是一段测试正文。", count: 40)),
            .paragraph(String(repeating: "Second paragraph. ", count: 30)),
        ])
        let pages = ChapterPager.paginate(
            book: BookDocument(title: "T", author: nil, language: "zh", chapters: [sample]),
            context: context()
        )[0].pages

        var covered = 0
        for (index, page) in pages.enumerated() {
            #expect(page.characterRange.location == covered, "第 \(index) 页起点不连续")
            covered += page.characterRange.length
        }
        #expect(covered == sample.textLength)
    }

    /// 分页切出的子串必须与按同一区间从原文截取的子串一致（不截断复合字符）。
    @Test func pageTextMatchesPlainTextSubstring() {
        let sample = chapter(id: "y", blocks: [
            .paragraph(String(repeating: "文字与 emoji 🙈 混排。", count: 30)),
        ])
        let pages = ChapterPager.paginate(
            book: BookDocument(title: "T", author: nil, language: "zh", chapters: [sample]),
            context: context()
        )[0].pages

        let full = sample.plainText as NSString
        for page in pages {
            #expect(page.text.string == full.substring(with: page.characterRange))
        }
    }

    /// 脚注角标不改变长度：加了 noteID 的 run 与纯文本 run 长度一致。
    @Test func noterefRunsDoNotChangeLength() {
        let plain = chapter(id: "p", blocks: [.paragraph(runs: [InlineRun("原文12继续")])])
        let annotated = chapter(id: "n", blocks: [.paragraph(runs: [
            InlineRun("原文"),
            InlineRun("12", noteID: "note12"),
            InlineRun("继续"),
        ])])
        #expect(plain.textLength == annotated.textLength)
        #expect(plain.plainText == annotated.plainText)
    }

    /// 极小容器下也不能死循环或丢内容。
    @Test func tinyContainerStillTerminates() {
        let sample = chapter(id: "t", blocks: [.paragraph(String(repeating: "你好世界。", count: 50))])
        let pages = ChapterPager.paginate(
            book: BookDocument(title: "T", author: nil, language: "zh", chapters: [sample]),
            context: context(width: 50, height: 10)
        )[0].pages
        // 只要有 contentRange 长度为正的页，就说明循环推进过
        #expect(pages.allSatisfy { $0.characterRange.length > 0 })
    }

    /// 整本书的 chapterStarts 必须与逐章长度一致 —— 进度条依赖它。
    @Test func chapterStartsMatchChapterLengths() {
        let chapters = [
            chapter(id: "1", blocks: [.paragraph("abc")]),
            chapter(id: "2", blocks: [.paragraph("de"), .paragraph("fg")]),
            chapter(id: "3", blocks: []),
        ]
        let document = BookDocument(title: "T", author: nil, language: "zh", chapters: chapters)
        var expected = [0]
        for item in chapters { expected.append(expected[expected.count - 1] + item.textLength) }
        #expect(document.chapterStarts == expected)
    }
}
