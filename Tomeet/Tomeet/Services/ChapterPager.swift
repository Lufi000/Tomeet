import Foundation
import SwiftUI
import UIKit

extension NSAttributedString.Key {
    /// 脚注角标携带的锚点 id。点击时用字符索引取它，再查 `BookDocument.anchors` 跳转。
    static let tomeetNoteref = NSAttributedString.Key("tomeetNoteref")
    /// 高亮区间携带的高亮 id（SwiftData `Highlight.id`），用于长按删除/改色。
    static let tomeetHighlight = NSAttributedString.Key("tomeetHighlight")
    /// 图片块的待加载载荷（`BookImagePayload`）。分页只挂引用，上屏才解码。
    static let tomeetImage = NSAttributedString.Key("tomeetImage")
}

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

/// 分页输入参数。pageSize 为**整屏**尺寸（旋转时重建）。
///
/// 页面本身顶到屏幕四边（Apple Books 的卷页效果），但正文不能压到灵动岛/Home 指示条，
/// 所以安全区作为**额外**内衬叠加在用户设置的边距之上，而不是缩掉 pageSize。
/// 分页与渲染必须用同一套内衬，否则文字会换行错位。
struct PaginationContext: Sendable, Equatable {
    var pageSize: CGSize
    var horizontalInset: CGFloat = 28
    var verticalInset: CGFloat = 36
    /// 屏幕安全区。由 View 层注入，叠加在 horizontalInset/verticalInset 之上。
    var safeAreaInsets: ContentInsets = .zero
    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = 8
    var paragraphSpacing: CGFloat = 12
    var firstLineIndent: CGFloat = 2.0
    var lineHeightMultiple: CGFloat = 1.55
    var theme: ReaderTheme = .original

    /// 正文实际可排版的矩形边距：用户边距 + 安全区。
    var resolvedInsets: ContentInsets {
        ContentInsets(
            top: verticalInset + safeAreaInsets.top,
            leading: horizontalInset + safeAreaInsets.leading,
            bottom: verticalInset + safeAreaInsets.bottom,
            trailing: horizontalInset + safeAreaInsets.trailing
        )
    }
}

/// 与 SwiftUI 解耦的四边内衬（`Sendable`，可在后台分页线程传递）。
struct ContentInsets: Sendable, Equatable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0

    static let zero = ContentInsets()

    init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    init(_ insets: UIEdgeInsets) {
        self.init(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }

    var uiEdgeInsets: UIEdgeInsets {
        UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
    }
}

/// TextKit 章节优先分页：每章从新页开始，章节绝不跨页。
/// `nonisolated`：纯计算，可在后台线程整书分页。
enum ChapterPager {
    /// dc:language 前缀为 en 时用衬线字体（Apple Books 惯例）；CJK 与未知语言使用系统默认（PingFang SC/TC）。
    static nonisolated func isCJKLanguage(_ language: String?) -> Bool {
        guard let language = language?.lowercased() else { return false }
        return language.hasPrefix("zh") || language.hasPrefix("ja") || language.hasPrefix("ko")
    }

    static nonisolated func isSerifLanguage(_ language: String?) -> Bool {
        language?.lowercased().hasPrefix("en") == true
    }

    static nonisolated func fontDescriptor(for language: String?) -> UIFontDescriptor {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        guard !isCJKLanguage(language), isSerifLanguage(language), let serif = descriptor.withDesign(.serif) else {
            return descriptor
        }
        return serif
    }

    static nonisolated func paginate(book: BookDocument, context: PaginationContext) -> [PaginatedChapter] {
        book.chapters.enumerated().map { index, chapter in
            PaginatedChapter(
                chapterIndex: index,
                pages: paginate(
                    chapter: chapter,
                    language: book.language,
                    baseURL: book.baseURL,
                    context: context
                )
            )
        }
    }

    private static nonisolated func uiColor(from color: Color) -> UIColor {
        UIColor(color)
    }

    // MARK: - 单章分页

    private static nonisolated func paginate(
        chapter: Chapter,
        language: String?,
        baseURL: URL?,
        context: PaginationContext
    ) -> [TextPage] {
        let attributed = makeAttributedText(chapter: chapter, language: language, baseURL: baseURL, context: context)
        let text = attributed.string as NSString
        guard text.length > 0 else { return [] }

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let insets = context.resolvedInsets
        let contentSize = CGSize(
            width: max(1, context.pageSize.width - insets.leading - insets.trailing),
            height: max(1, context.pageSize.height - insets.top - insets.bottom)
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

    /// 把插图缩放到能放进一页。
    ///
    /// **上限是硬约束**：比正文容器还高的图会撑不进任何一行，TextKit 在该容器上返回空
    /// glyph range，分页循环据此 break —— 整章后半部分会被静默丢掉。
    private static nonisolated func fittedImageSize(
        pixelSize: CGSize,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0, maxWidth > 0, maxHeight > 0 else { return .zero }
        let scale = min(1, min(maxWidth / pixelSize.width, maxHeight / pixelSize.height))
        return CGSize(width: (pixelSize.width * scale).rounded(), height: (pixelSize.height * scale).rounded())
    }

    private static nonisolated func makeAttributedText(
        chapter: Chapter,
        language: String?,
        baseURL: URL?,
        context: PaginationContext
    ) -> NSAttributedString {
        let baseFont = UIFont(descriptor: fontDescriptor(for: language), size: context.fontSize)
        let isCJK = isCJKLanguage(language)
        let textColor = uiColor(from: context.theme.textColor)
        let accentColor = uiColor(from: context.theme.accentColor)
        let noteFont = UIFont(descriptor: baseFont.fontDescriptor, size: context.fontSize * 0.65)
        let insets = context.resolvedInsets

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

        let quoteFont: UIFont
        if isCJK {
            quoteFont = UIFont(descriptor: baseFont.fontDescriptor, size: context.fontSize)
        } else {
            quoteFont = emphasized(baseFont, .italic, isCJK: false)
        }

        let result = NSMutableAttributedString()

        // 块之间用 "\n" 连接 —— 必须与 Chapter.plainText 完全一致，
        // 否则分页给出的 NSRange 无法映射回 canonical 偏移（高亮锚点会整体错位）。
        for (index, block) in chapter.blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            switch block {
            case let .heading(level, runs):
                let size = context.fontSize + CGFloat(max(0, 4 - level)) * 2  // h1 最大
                let headingFont = emphasized(
                    UIFont(descriptor: baseFont.fontDescriptor, size: size),
                    .bold,
                    isCJK: isCJK
                )
                let color = level >= 2 ? accentColor : textColor
                append(runs, to: result, font: headingFont, style: headingStyle,
                       color: color, accentColor: accentColor, noteFont: noteFont, isCJK: isCJK)

            case let .paragraph(runs):
                append(runs, to: result, font: baseFont, style: bodyStyle,
                       color: textColor, accentColor: accentColor, noteFont: noteFont, isCJK: isCJK)

            case let .quote(runs):
                append(runs, to: result, font: quoteFont, style: quoteStyle,
                       color: textColor, accentColor: accentColor, noteFont: noteFont, isCJK: isCJK)

            case let .image(ref):
                result.append(imageAttachment(ref, baseURL: baseURL, context: context, insets: insets))
            }
        }
        return result
    }

    /// 追加一组内联 run。脚注角标用强调色 + 上标渲染，但**文字本身不变**（长度守恒）。
    private static nonisolated func append(
        _ runs: [InlineRun],
        to result: NSMutableAttributedString,
        font: UIFont,
        style: NSParagraphStyle,
        color: UIColor,
        accentColor: UIColor,
        noteFont: UIFont,
        isCJK: Bool
    ) {
        for run in runs {
            guard !run.text.isEmpty else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: style,
            ]
            if let noteID = run.noteID {
                // 上标角标：缩小字号 + 抬升基线 + 强调色，对齐 Apple Books。
                attributes[.font] = noteFont
                attributes[.foregroundColor] = accentColor
                attributes[.baselineOffset] = noteFont.pointSize * 0.45
                attributes[.tomeetNoteref] = noteID
            } else {
                attributes[.font] = emphasized(font, run.emphasis, isCJK: isCJK)
                attributes[.foregroundColor] = color
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
    }

    /// 按强调加载字体。CJK 字体没有真斜体，合成斜体会被系统拉斜、观感差，
    /// 所以 CJK 下不施加 italic（与引文块的既有处理一致），bold 照常。
    private static nonisolated func emphasized(
        _ base: UIFont,
        _ emphasis: InlineRun.Emphasis,
        isCJK: Bool
    ) -> UIFont {
        switch emphasis {
        case .none:
            return base
        case .bold:
            return withTraits(base, .traitBold)
        case .italic:
            return isCJK ? base : withTraits(base, .traitItalic)
        case .boldItalic:
            return isCJK ? withTraits(base, .traitBold) : withTraits(base, [.traitBold, .traitItalic])
        }
    }

    private static nonisolated func withTraits(
        _ base: UIFont,
        _ traits: UIFontDescriptor.SymbolicTraits
    ) -> UIFont {
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// 图片块 → 文本附件。
    ///
    /// **分页阶段不解码位图**：只读文件头拿像素尺寸来算排版，把 `ImageRef` 挂在附件上，
    /// 等这一页真正上屏时再由 `BookImageLoader` 降采样解码。
    /// 否则「分页整本书」会顺带把整本书的图都解码进内存。
    ///
    /// 拿不到尺寸时退化成一个同样占 U+FFFC 的空附件，长度仍与 `Block.text` 一致。
    private static nonisolated func imageAttachment(
        _ ref: ImageRef,
        baseURL: URL?,
        context: PaginationContext,
        insets: ContentInsets
    ) -> NSAttributedString {
        let maxWidth = max(1, context.pageSize.width - insets.leading - insets.trailing)
        // 留出余量：图片独占一行，还要容纳行距等，撑满整页高会让它挤不进任何容器。
        let maxHeight = max(1, (context.pageSize.height - insets.top - insets.bottom) * 0.85)

        let attachment = NSTextAttachment()
        attachment.accessibilityLabel = ref.alt
        if let pixelSize = BookImageLoader.pixelSize(of: ref, baseURL: baseURL) {
            attachment.bounds = CGRect(
                origin: .zero,
                size: fittedImageSize(pixelSize: pixelSize, maxWidth: maxWidth, maxHeight: maxHeight)
            )
        }

        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttribute(
            .tomeetImage,
            value: BookImagePayload(ref: ref, baseURL: baseURL),
            range: NSRange(location: 0, length: result.length)
        )
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
