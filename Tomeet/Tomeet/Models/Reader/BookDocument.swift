import Foundation

/// 书中一个文本块：标题（h1–h6）/ 段落 / 引文（含剧中对话）。
enum Block: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)

    var text: String {
        switch self {
        case let .heading(_, text), let .paragraph(text), let .quote(text): text
        }
    }

    var length: Int { text.count }
}

/// 一章：标题 + 按 spine 顺序的文本块。`id` 为清单中 href 去扩展名，用于 Contents 稳定标识。
struct Chapter: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let blocks: [Block]

    var textLength: Int { blocks.reduce(0) { $0 + $1.length } }
}

/// 全书：spine 顺序章节 + 预计算的全书字符位置表。
struct BookDocument: Sendable {
    let title: String
    let author: String?
    let language: String?
    let chapters: [Chapter]

    /// `chapterStarts[i]` = 第 i 章第一个字符在全书文本中的偏移；`count == chapters.count + 1`，末位为全书字符数。
    let chapterStarts: [Int]

    var totalCharacters: Int { chapterStarts.last ?? 0 }

    init(title: String, author: String?, language: String?, chapters: [Chapter]) {
        self.title = title
        self.author = author
        self.language = language
        self.chapters = chapters
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
