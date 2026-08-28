import Foundation

/// 一份本地 AI 讲书内容（对应一本书的一个语言版本）。
///
/// 数据结构与 `docs/design/book_summary.md` §3.2 的导读清单对齐：
/// 以主题章节组织，每节包含标题、口语化文字稿与指向原文的引用定位。
/// 当前阶段内容由人工审校的本地 fixture 提供，不依赖网络。
struct BookNarration: Codable, Identifiable, Sendable, Equatable {
    let schemaVersion: String
    let bookID: String
    let locale: String
    let title: String
    let subtitle: String
    let sections: [NarrationSection]

    var id: String { "\(bookID)-\(locale)" }
    var totalDuration: TimeInterval {
        sections.reduce(0) { $0 + $1.duration }
    }
}

/// 讲书中的一个主题章节。
struct NarrationSection: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let transcript: String
    /// 预计朗读时长（秒）。
    let duration: TimeInterval
    /// 指向原文的引用定位（至少一节一个，可空）。
    var citations: [NarrationCitation] = []
}

/// 观点对应的原文引用：定位到 EPUB spine 章节索引（0 基）。
struct NarrationCitation: Codable, Sendable, Equatable, Identifiable {
    let chapterIndex: Int
    let chapterTitle: String
    let excerpt: String?

    var id: String { "\(chapterIndex)" }
}
