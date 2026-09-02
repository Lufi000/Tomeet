import Foundation
import SwiftUI
import UIKit

/// 一页渲染内容：排版后的文本 + 该页在所属章节全文字符串中的绝对字符区间。
struct TextPage: Sendable {
    let text: NSAttributedString
    let characterRange: NSRange
}

/// 一章的分页结果。
struct PaginatedChapter: Sendable {
    let chapterIndex: Int
    let pages: [TextPage]
}

/// 分页输入参数。pageSize 为承载容器尺寸（旋转时重建）。
struct PaginationContext: Sendable, Equatable {
    var pageSize: CGSize
    var horizontalInset: CGFloat = 28
    var verticalInset: CGFloat = 36
    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = 8
    var paragraphSpacing: CGFloat = 12
    var firstLineIndent: CGFloat = 2.0
    var lineHeightMultiple: CGFloat = 1.55
    var theme: ReaderTheme = .original
}

/// TextKit 章节优先分页：每章从新页开始，章节绝不跨页。
/// `nonisolated`：纯计算，可在后台线程整书分页。
enum ChapterPager {
    /// dc:language 前缀为 zh/ja/ko 视为 CJK（影响首行缩进等排版）。
    static nonisolated func isCJKLanguage(_ language: String?) -> Bool {
        guard let language = language?.lowercased() else { return false }
        return language.hasPrefix("zh") || language.hasPrefix("ja") || language.hasPrefix("ko")
    }

    /// 正文统一用系统默认字体（中文苹方 / 英文 SF），长时间阅读比衬线更舒服。
    static nonisolated func fontDescriptor(for language: String?) -> UIFontDescriptor {
        UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
    }

    static nonisolated func paginate(book: BookDocument, context: PaginationContext) -> [PaginatedChapter] {
        book.chapters.enumerated().map { index, chapter in
            PaginatedChapter(chapterIndex: index, pages: paginate(chapter: chapter, language: book.language, context: context))
        }
    }

    private static nonisolated func uiColor(from color: Color) -> UIColor {
        UIColor(color)
    }

    // MARK: - 单章分页

    private static nonisolated func paginate(chapter: Chapter, language: String?, context: PaginationContext) -> [TextPage] {
        let attributed = makeAttributedText(chapter: chapter, language: language, context: context)
        let text = attributed.string as NSString
        guard text.length > 0 else { return [] }

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let contentSize = CGSize(
            width: max(1, context.pageSize.width - context.horizontalInset * 2),
            height: max(1, context.pageSize.height - context.verticalInset * 2)
        )

        var pages: [TextPage] = []
        var nextCharacter = 0
        let totalLength = text.length

        while nextCharacter < totalLength {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            // 字形↔字符往返：确保页面不截断字符（复合字符/连字安全）
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard characterRange.length > 0 else { break }  // 容器放不下任何内容：防死循环

            let pageAttributed = attributed.attributedSubstring(from: characterRange)
            pages.append(TextPage(text: pageAttributed, characterRange: characterRange))
            nextCharacter = characterRange.location + characterRange.length
        }
        return pages
    }

    // MARK: - 排版文本

    private static nonisolated func makeAttributedText(chapter: Chapter, language: String?, context: PaginationContext) -> NSAttributedString {
        let baseFont = UIFont(descriptor: fontDescriptor(for: language), size: context.fontSize)
        let isCJK = isCJKLanguage(language)
        let textColor = uiColor(from: context.theme.textColor)
        let accentColor = uiColor(from: context.theme.accentColor)

        let bodyStyle = paragraphStyle(
            lineSpacing: context.lineSpacing,
            lineHeightMultiple: context.lineHeightMultiple,
            paragraphSpacing: context.paragraphSpacing,
            firstLineIndent: context.fontSize * context.firstLineIndent
        )
        let headingStyle = paragraphStyle(
            lineSpacing: context.lineSpacing,
            lineHeightMultiple: context.lineHeightMultiple,
            paragraphSpacing: context.paragraphSpacing,
            paragraphSpacingBefore: context.paragraphSpacing * 1.5
        )
        let quoteStyle = paragraphStyle(
            lineSpacing: context.lineSpacing,
            lineHeightMultiple: context.lineHeightMultiple,
            paragraphSpacing: context.paragraphSpacing,
            indent: 16
        )

        let result = NSMutableAttributedString()

        for (index, block) in chapter.blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            switch block {
            case let .heading(level, text):
                let size = context.fontSize + CGFloat(max(0, 4 - level)) * 2  // h1 最大
                let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? baseFont.fontDescriptor
                let font = UIFont(descriptor: boldDescriptor, size: size)
                let color = level >= 2 ? accentColor : textColor
                result.append(NSAttributedString(
                    string: text,
                    attributes: [.font: font, .paragraphStyle: headingStyle, .foregroundColor: color]
                ))
            case let .paragraph(text):
                result.append(NSAttributedString(
                    string: text,
                    attributes: [.font: baseFont, .paragraphStyle: bodyStyle, .foregroundColor: textColor]
                ))
            case let .quote(text):
                let quoteFont: UIFont
                if isCJK {
                    quoteFont = UIFont(descriptor: baseFont.fontDescriptor, size: context.fontSize)
                } else {
                    let italicDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
                    quoteFont = UIFont(descriptor: italicDescriptor, size: context.fontSize)
                }
                result.append(NSAttributedString(
                    string: text,
                    attributes: [.font: quoteFont, .paragraphStyle: quoteStyle, .foregroundColor: textColor]
                ))
            }
        }
        return result
    }

    private static nonisolated func paragraphStyle(
        lineSpacing: CGFloat,
        lineHeightMultiple: CGFloat,
        paragraphSpacing: CGFloat,
        paragraphSpacingBefore: CGFloat = 0,
        firstLineIndent: CGFloat = 0,
        indent: CGFloat = 0
    ) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineHeightMultiple = lineHeightMultiple
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.paragraphSpacingBefore = paragraphSpacingBefore
        if firstLineIndent > 0 {
            paragraph.firstLineHeadIndent = firstLineIndent
        }
        if indent > 0 {
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent
        }
        return paragraph
    }
}
