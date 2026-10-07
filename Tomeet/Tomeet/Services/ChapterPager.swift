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
    /// 引文区间标记：渲染端据此在缩进槽里画左侧竖线。
    static let tomeetQuote = NSAttributedString.Key("tomeetQuote")
}

/// 一页渲染内容：排版后的文本 + 该页在所属章节全文字符串中的绝对字符区间。
struct TextPage: Sendable {
    let text: NSAttributedString
    let characterRange: NSRange
    /// 章首页顶部的章标题；非首页为 nil。
    let header: PageHeader?

    init(text: NSAttributedString, characterRange: NSRange, header: PageHeader? = nil) {
        self.text = text
        self.characterRange = characterRange
        self.header = header
    }
}

/// 章首页顶部排好的章标题。
///
/// **标题不进 `TextPage.text`** —— 正文串必须与 `Chapter.plainText` 逐字对应，
/// 高亮、书签、阅读位置的字符偏移全靠这个对应关系换算。标题挂在页上，
/// 只占高度、不占字符：分页时从首页扣掉它的高度，渲染时按同一高度把正文下移。
///
/// 高度、线宽这些都由分页端量好传过来，渲染端照着摆 —— 不让两端各自算。
struct PageHeader: Sendable, Equatable {
    /// 已排好字体/字号/颜色/段落样式的标题本体。
    let text: NSAttributedString
    /// 标题文字块高度（左侧竖线按它画）。
    let titleHeight: CGFloat
    /// 标题区总高度（标题 + 与正文之间的留白）。渲染端按它把正文下移。
    let totalHeight: CGFloat
    /// 左侧竖线宽度。
    let ruleWidth: CGFloat
    /// 竖线槽宽度：线宽 + 线到文字的间距。
    let ruleGutter: CGFloat

    var title: String { text.string }
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

    /// 正文基准字体。章标题等派生字体都从这里出去，保证同源。
    private static nonisolated func baseFont(language: String?, size: CGFloat) -> UIFont {
        UIFont(descriptor: fontDescriptor(for: language), size: size)
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
        let header = chapterHeader(chapter: chapter, language: language, context: context)

        var pages: [TextPage] = []
        var nextCharacter = 0
        let totalLength = text.length

        while nextCharacter < totalLength {
            let isFirstPage = pages.isEmpty
            var pageHeader = isFirstPage ? header : nil
            var container = makeContainer(
                size: CGSize(width: contentSize.width, height: contentSize.height - (pageHeader?.totalHeight ?? 0))
            )
            layoutManager.addTextContainer(container)
            var glyphRange = layoutManager.glyphRange(for: container)

            // 首页被标题挤到一行都放不下时放弃标题：宁可这章首页没有大标题，
            // 也不能让空容器走到下面的 break —— 那会把整章剩下的文字全丢掉。
            if pageHeader != nil, glyphRange.length == 0 {
                pageHeader = nil
                layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
                container = makeContainer(size: contentSize)
                layoutManager.addTextContainer(container)
                glyphRange = layoutManager.glyphRange(for: container)
            }

            // 字形↔字符往返：确保页面不截断字符（复合字符/连字安全）
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard characterRange.length > 0 else { break }  // 容器放不下任何内容：防死循环

            let pageAttributed = pageText(
                from: attributed,
                range: characterRange,
                startsMidParagraph: characterRange.location > 0
                    && text.character(at: characterRange.location - 1) != Self.newline
            )
            pages.append(TextPage(text: pageAttributed, characterRange: characterRange, header: pageHeader))
            nextCharacter = characterRange.location + characterRange.length
        }
        return pages
    }

    private static let newline = unichar(0x0A)

    /// 裁出这一页的排版串，并修掉「页首被当成段落首行」的那个缩进。
    ///
    /// **分页和上屏在这里曾经算的不是同一条行宽。** 分页时整章是一个字符串，页首那一行前面
    /// 还有内容，TextKit 不把它当段落首行，不缩进；上屏时这一页是**独立字符串**，页首那行
    /// 就成了段落首行，被套上 `firstLineHeadIndent`（默认 2 字 = 34pt）。首行因此少排两个字，
    /// 多出来的字挤到下一行，页尾那一行就装不下被裁掉 —— 用户看到的「每翻一页末尾丢一点」。
    ///
    /// 修法：页首落在段落中段时，把本页第一段的首行缩进抹平成 `headIndent`
    /// （正文是 0，引文本来就是 28，标题是 0，都正好）。页首本来起新段时不改 —— 那时的缩进是对的。
    ///
    /// 代价：这类页会比分页时少排约两个字（分页按未缩进算的）。
    /// 宁可每页末尾空一点，也不能把字裁掉。
    private static nonisolated func pageText(
        from attributed: NSAttributedString,
        range: NSRange,
        startsMidParagraph: Bool
    ) -> NSAttributedString {
        let page = attributed.attributedSubstring(from: range)
        guard startsMidParagraph, page.length > 0 else { return page }

        let plain = page.string as NSString
        let breakIndex = plain.range(of: "\n").location
        let firstParagraphLength = breakIndex == NSNotFound ? page.length : breakIndex
        guard firstParagraphLength > 0 else { return page }

        let mutable = NSMutableAttributedString(attributedString: page)
        mutable.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: firstParagraphLength)) { value, subrange, _ in
            guard let style = value as? NSParagraphStyle,
                  style.firstLineHeadIndent != style.headIndent,
                  let adjusted = style.mutableCopy() as? NSMutableParagraphStyle
            else { return }
            // 必须拷贝：整章共用同一个 style 实例，原地改会污染全书。
            adjusted.firstLineHeadIndent = style.headIndent
            mutable.addAttribute(.paragraphStyle, value: adjusted, range: subrange)
        }
        return mutable
    }

    private static nonisolated func makeContainer(size: CGSize) -> NSTextContainer {
        let container = NSTextContainer(size: CGSize(width: max(1, size.width), height: max(1, size.height)))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        return container
    }

    // MARK: - 章标题

    // MARK: - 引文几何

    /// 引文正文相对正文左边距的额外缩进。
    static let quoteTextIndent: CGFloat = 28
    /// 引文竖线距正文左边距的偏移（竖线画在缩进槽的左端）。
    static let quoteRuleInset: CGFloat = 12
    /// 引文竖线宽度。
    static let quoteRuleWidth: CGFloat = 2
    /// 引文竖线颜色相对正文墨色的透明度。
    static let quoteRuleOpacity: CGFloat = 0.4
    /// 引文字号相对正文小多少 pt。
    private static let quoteFontSizeDelta: CGFloat = 1
    /// 引文墨色透明度（弱一档）。
    private static let quoteInkOpacity: CGFloat = 0.75

    /// 章标题字号相对正文字号的倍数。跟正文同源派生，用户改字号时标题跟着变。
    private static let chapterTitleScale: CGFloat = 1.5
    /// 左侧竖线宽度。
    private static let chapterTitleRuleWidth: CGFloat = 3
    /// 竖线槽宽度：线宽 + 线到文字的间距。
    private static let chapterTitleRuleGutter: CGFloat = 12

    /// 章节首页的章标题；这章不排标题时返回 nil。
    private static nonisolated func chapterHeader(
        chapter: Chapter,
        language: String?,
        context: PaginationContext
    ) -> PageHeader? {
        let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !startsWithItsOwnTitle(chapter: chapter, title: title) else { return nil }

        let insets = context.resolvedInsets
        let contentWidth = max(1, context.pageSize.width - insets.leading - insets.trailing)
        let font = emphasized(
            baseFont(language: language, size: context.fontSize * chapterTitleScale),
            .bold,
            isCJK: isCJKLanguage(language)
        )
        let attributed = NSAttributedString(string: title, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle(
                lineSpacing: context.lineSpacing,
                lineHeightMultiple: context.lineHeightMultiple,
                paragraphSpacing: 0
            ),
            .foregroundColor: uiColor(from: context.theme.accentColor),
        ])

        // 量一次高度给渲染端用。渲染端不重算 —— 两端各自量必然出现 ±1pt 的差，
        // 那正是「翻页吞字」那个 bug 的成因。
        let textHeight = ceil(attributed.boundingRect(
            with: CGSize(
                width: max(1, contentWidth - chapterTitleRuleGutter),
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)

        return PageHeader(
            text: attributed,
            titleHeight: textHeight,
            totalHeight: textHeight + context.paragraphSpacing * 2,
            ruleWidth: chapterTitleRuleWidth,
            ruleGutter: chapterTitleRuleGutter
        )
    }

    /// 章首第一个块就是本章标题时不再另排标题 —— 否则同一行字出现两次。
    ///
    /// 真目录拿不到时，解析器会拿章内首个 heading 当目录标题的回退，这类书很常见。
    /// 目录标题常带年份/卷次（「3 我的低谷（1979—1982年）」）而章内 h1 只写主标题，
    /// 所以互相包含也算同一行；但要够长才比，避免「1」这种短标题误判。
    private static nonisolated func startsWithItsOwnTitle(chapter: Chapter, title: String) -> Bool {
        guard case let .heading(_, runs) = chapter.blocks.first else { return false }
        let headingText = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headingText.isEmpty else { return false }
        if headingText == title { return true }
        let shorter = headingText.count <= title.count ? headingText : title
        let longer = headingText.count <= title.count ? title : headingText
        return shorter.count >= 4 && longer.contains(shorter)
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
        let baseFont = baseFont(language: language, size: context.fontSize)
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
            indent: Self.quoteTextIndent
        )

        // 引文比正文低一档：字号小 1pt、墨色弱一档、左缩进 + 左侧竖线。
        // 中文书原来只有 16pt 缩进，跟正文几乎分不出来。
        let quoteFontSize = max(1, context.fontSize - Self.quoteFontSizeDelta)
        let quoteFont: UIFont
        if isCJK {
            quoteFont = UIFont(descriptor: baseFont.fontDescriptor, size: quoteFontSize)
        } else {
            quoteFont = emphasized(
                UIFont(descriptor: baseFont.fontDescriptor, size: quoteFontSize),
                .italic,
                isCJK: false
            )
        }
        let quoteColor = textColor.withAlphaComponent(Self.quoteInkOpacity)

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
                       color: quoteColor, accentColor: accentColor, noteFont: noteFont, isCJK: isCJK,
                       isQuote: true)

            case let .image(ref):
                result.append(imageAttachment(ref, baseURL: baseURL, context: context, insets: insets))
            }
        }
        resolveFallbackFonts(in: result)
        return result
    }

    // MARK: - 字体回退显式化

    /// 把「系统字体回退」提前算出来，显式写回属性里。**分页能不能和上屏对上，全看这一步。**
    ///
    /// 分页跑在 TextKit 1（`NSLayoutManager`）上，量行高用的是属性里**声明的字体**；
    /// 上屏的 UITextView（iOS 16+ 是 TextKit 2）按**真正落笔的字体**排行。中文正文声明的是
    /// 西文字体（New York / SF UI），真正画字形的是系统回退的中文字体 —— 两者行高不同：
    /// 实测每一行差约 1.7pt（39.4 vs 41.1），乘上十几行就是一整行。分页以为这页装得下，
    /// 上屏却装不下，容器把最后一行裁掉 —— 用户看到的就是「每翻一页末尾吞掉一截」。
    ///
    /// 显式写回后两边量到的是同一套字体，分页与上屏必然一致。西文书的字符声明字体自己就能画，
    /// 一个属性都不会改（拉丁文仍走 New York / SF UI，观感不变）；只有画不出的字
    /// （中文书的正文）会被钉死成实际落笔的那个字体。
    private static nonisolated func resolveFallbackFonts(in attributed: NSMutableAttributedString) {
        let text = attributed.string as NSString
        // 回退结果是 (声明字体, 字符) 的函数，而字符的重复率极高 —— 缓存后
        // 整本书只需要几千次 CoreText 调用，不是几十万次。
        var cache: [FallbackKey: UIFont] = [:]

        var index = 0
        while index < attributed.length {
            var declaredRange = NSRange(location: 0, length: 0)
            guard let declared = attributed.attribute(.font, at: index, effectiveRange: &declaredRange) as? UIFont else {
                // 图片附件的 U+FFFC 没有字体属性，跳过。
                index += 1
                continue
            }
            let runEnd = min(NSMaxRange(declaredRange), attributed.length)

            var cursor = index
            while cursor < runEnd {
                let spanStart = cursor
                let spanFont = resolvedFont(declared, at: cursor, in: text, cache: &cache)
                cursor += character(in: text, at: cursor).length

                // 同一种回退字体的连续字符合成一个区间写一次，避免把属性串打碎成逐字 run。
                while cursor < runEnd {
                    let next = resolvedFont(declared, at: cursor, in: text, cache: &cache)
                    guard next == spanFont else { break }
                    cursor += character(in: text, at: cursor).length
                }

                if spanFont != declared {
                    attributed.addAttribute(.font, value: spanFont, range: NSRange(location: spanStart, length: cursor - spanStart))
                }
            }
            index = runEnd
        }
    }

    /// 缓存键：同一个字体对同一个字符的回退结果是稳定的。
    private struct FallbackKey: Hashable {
        let font: UIFont
        let scalar: UInt32
    }

    private static nonisolated func resolvedFont(
        _ declared: UIFont,
        at index: Int,
        in text: NSString,
        cache: inout [FallbackKey: UIFont]
    ) -> UIFont {
        let (scalar, length) = character(in: text, at: index)
        let key = FallbackKey(font: declared, scalar: scalar)
        if let cached = cache[key] { return cached }
        let resolved = CTFontCreateForString(
            declared as CTFont,
            text,
            CFRange(location: index, length: length)
        ) as UIFont
        cache[key] = resolved
        return resolved
    }

    /// `index` 处的完整字符：标量值（做缓存键）+ 占用的 UTF-16 长度。代理对算一个字符 ——
    /// 拆开取回退字体的话，emoji 这种补充平面字符会被查成两个不相干的字体。
    private static nonisolated func character(in text: NSString, at index: Int) -> (scalar: UInt32, length: Int) {
        let unit = text.character(at: index)
        guard unit >= 0xD800, unit <= 0xDBFF, index + 1 < text.length else {
            return (UInt32(unit), 1)
        }
        let low = text.character(at: index + 1)
        guard low >= 0xDC00, low <= 0xDFFF else { return (UInt32(unit), 1) }
        let scalar = 0x10000 + (UInt32(unit - 0xD800) << 10) + UInt32(low - 0xDC00)
        return (scalar, 2)
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
        isCJK: Bool,
        isQuote: Bool = false
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
            if isQuote {
                attributes[.tomeetQuote] = true
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
