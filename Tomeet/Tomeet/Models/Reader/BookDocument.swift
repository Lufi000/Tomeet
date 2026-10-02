import Foundation

/// 内联片段：一段文本 + 强调 + 可选的脚注锚点。
///
/// 拆成 run 而不是一个裸 String，是因为**脚注角标**和**图片**必须进入正文 ——
/// 旧的纯字符串模型在解析时把它们拍平/丢弃了（bug.md：角标显示不对、图片不显示）。
struct InlineRun: Sendable, Equatable {
    enum Emphasis: Sendable, Equatable {
        case none
        case italic
        case bold
        case boldItalic
    }

    var text: String
    var emphasis: Emphasis
    /// 脚注锚点 id（`<a epub:type="noteref" href="#note12">` → `"note12"`）。
    ///
    /// 角标文字就是 `text` 本身（原文自带的编号），所以标脚注**不改变字符长度**，
    /// 高亮/阅读位置的偏移不会因此漂移。
    var noteID: String?

    init(_ text: String, emphasis: Emphasis = .none, noteID: String? = nil) {
        self.text = text
        self.emphasis = emphasis
        self.noteID = noteID
    }
}

/// 块级插图。`path` 相对书源根目录（`BookDocument.baseURL`）。
struct ImageRef: Sendable, Equatable {
    var path: String
    var alt: String?

    init(path: String, alt: String? = nil) {
        self.path = path
        self.alt = alt
    }
}

/// 书中一个块：标题（h1–h6）/ 段落 / 引文 / 插图。
///
/// case 带 `runs:` 标签是为了让下面的便捷工厂（`paragraph(_:)` 等）与 case 构造器共存 ——
/// 大量既有代码和测试用 `.paragraph("文本")` 构造，保留它们就不必改 28 处调用点。
enum Block: Sendable, Equatable {
    case heading(level: Int, runs: [InlineRun])
    case paragraph(runs: [InlineRun])
    case quote(runs: [InlineRun])
    case image(ImageRef)

    // MARK: - 便捷构造（纯文本，无强调/锚点）

    static func heading(level: Int, text: String) -> Block {
        .heading(level: level, runs: [InlineRun(text)])
    }

    static func paragraph(_ text: String) -> Block {
        .paragraph(runs: [InlineRun(text)])
    }

    static func quote(_ text: String) -> Block {
        .quote(runs: [InlineRun(text)])
    }

    // MARK: - 文本投影

    /// 内联片段。图片块没有 run（它在正文里只占一个 U+FFFC）。
    var runs: [InlineRun] {
        switch self {
        case let .heading(_, runs), let .paragraph(runs), let .quote(runs):
            return runs
        case .image:
            return []
        }
    }

    /// 该块贡献的正文文本。
    ///
    /// 图片贡献 U+FFFC（对象替换符）—— 与 `NSTextAttachment` 在 attributed string 里
    /// 占用的字符一致，这样「纯文本长度」和「渲染后长度」永远相等。
    var text: String {
        switch self {
        case let .heading(_, runs), let .paragraph(runs), let .quote(runs):
            return runs.map(\.text).joined()
        case .image:
            return "\u{FFFC}"
        }
    }

    /// UTF-16 长度。**必须**用 UTF-16：分页结果是 `NSRange`（UTF-16 code unit），
    /// 而 `String.count` 是字素簇，emoji / 罕用字下两者不等。
    var length: Int { text.utf16.count }

    /// 块内是否有需要渲染成图片的内容。
    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

/// 一章：标题 + 按 spine 顺序的块。
struct Chapter: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let blocks: [Block]

    /// 本章纯文本：块以 `\n` 连接。
    ///
    /// 这是**唯一真相源** —— `ChapterPager` 渲染出的 attributed string 与它逐字符对应，
    /// 所以高亮锚点能 1:1 映射成 NSRange。
    nonisolated var plainText: String {
        blocks.map(\.text).joined(separator: "\n")
    }

    /// UTF-16 长度，与 `NSAttributedString.length` 同构。
    nonisolated var textLength: Int { plainText.utf16.count }
}

/// 全书：spine 顺序章节 + 预计算的全书字符位置表。
struct BookDocument: Sendable {
    let title: String
    let author: String?
    let language: String?
    let chapters: [Chapter]

    /// 书源根目录（已解压 EPUB 的目录）。图片相对它解析。
    let baseURL: URL?

    /// 锚点 id → 位置。脚注跳转用它（`href="#x"` 的 `x` 指向这里）。
    let anchors: [String: ReaderLocation]

    /// `chapterStarts[i]` = 第 i 章第一个字符在全书文本中的偏移；`count == chapters.count + 1`，末位为全书字符数。
    let chapterStarts: [Int]

    var totalCharacters: Int { chapterStarts.last ?? 0 }

    /// 后台解析线程（EPUBParser）直接构造，非 MainActor。
    nonisolated init(
        title: String,
        author: String?,
        language: String?,
        chapters: [Chapter],
        baseURL: URL? = nil,
        anchors: [String: ReaderLocation] = [:]
    ) {
        self.title = title
        self.author = author
        self.language = language
        self.chapters = chapters
        self.baseURL = baseURL
        self.anchors = anchors
        var starts: [Int] = [0]
        for chapter in chapters {
            starts.append(starts[starts.count - 1] + chapter.textLength)
        }
        self.chapterStarts = starts
    }

    /// 位置 → 全书进度 0…1（越界自动夹紧到 [0,1]）。
    func progress(at location: ReaderLocation) -> Double {
        guard !chapters.isEmpty else { return 0 }
        let chapter = min(max(location.chapterIndex, 0), chapters.count - 1)
        let length = chapters[chapter].textLength
        let offset = min(max(location.charOffset, 0), length)
        let numerator = chapterStarts[chapter] + offset
        return totalCharacters == 0 ? 0 : Double(numerator) / Double(totalCharacters)
    }

    /// 全书进度 0…1 → 位置（负值/超值夹紧）。
    func location(atProgress progress: Double) -> ReaderLocation {
        guard !chapters.isEmpty else { return ReaderLocation(chapterIndex: 0, charOffset: 0) }
        let clamped = min(max(progress, 0), 1)
        let target = Double(totalCharacters) * clamped
        var chapter = chapters.count - 1
        for index in 0..<chapters.count where Double(chapterStarts[index + 1]) >= target {
            chapter = index
            break
        }
        let length = chapters[chapter].textLength
        let offset = min(max(Int(target) - chapterStarts[chapter], 0), length)
        return ReaderLocation(chapterIndex: chapter, charOffset: offset)
    }
}
