import Foundation
import SwiftData
import UIKit

/// 高亮颜色。用半透明色叠在正文底色上 —— Apple Books 的四色也是这么处理的，
/// 同一个色值要能在浅色（Paper）和深色主题下都读得清。
enum HighlightColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case yellow
    case green
    case blue
    case pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        }
    }

    /// 渲染用底色。alpha 让文字保持可读，不必为每套主题各配一个色值。
    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor(red: 1.00, green: 0.83, blue: 0.25, alpha: 0.42)
        case .green: UIColor(red: 0.47, green: 0.79, blue: 0.42, alpha: 0.42)
        case .blue: UIColor(red: 0.40, green: 0.65, blue: 0.95, alpha: 0.42)
        case .pink: UIColor(red: 0.95, green: 0.50, blue: 0.68, alpha: 0.42)
        }
    }
}

/// 书签：钉在**某一页**上（Apple Books 的书签就是页级，不是文字级）。
///
/// 锚点用 `ReaderLocation` 的坐标系：章内 canonical UTF-16 偏移。
/// 这样改字号/边距/换设备后重新分页，书签仍然落在原来的文字处，而不是"第 42 页"。
@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID
    /// `Book.id`。
    var bookID: UUID
    var chapterIndex: Int
    var charOffset: Int
    var createdAt: Date
    /// 书签处的正文片段，用于列表预览。
    var snippet: String

    init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterIndex: Int,
        charOffset: Int,
        createdAt: Date = .now,
        snippet: String = ""
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.charOffset = charOffset
        self.createdAt = createdAt
        self.snippet = snippet
    }

    var location: ReaderLocation {
        ReaderLocation(chapterIndex: chapterIndex, charOffset: charOffset)
    }
}

/// 高亮：一段被标记的文字，可附笔记。
@Model
final class Highlight {
    @Attribute(.unique) var id: UUID
    /// `Book.id`。
    var bookID: UUID
    var chapterIndex: Int
    /// 章内 canonical UTF-16 偏移，与 `ReaderLocation.charOffset` 同坐标系。
    var charOffset: Int
    /// UTF-16 长度。零长度的高亮无意义，插入前必须保证 > 0。
    var length: Int
    var colorRaw: String
    /// 被高亮的原文，列表里直接展示（不必回头去书里重新截取）。
    var text: String
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterIndex: Int,
        charOffset: Int,
        length: Int,
        color: HighlightColor = .yellow,
        text: String,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.charOffset = charOffset
        self.length = length
        self.colorRaw = color.rawValue
        self.text = text
        self.note = note
        self.createdAt = createdAt
    }

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue }
    }

    /// 本章内的字符区间，供渲染时与页区间求交。
    var range: NSRange { NSRange(location: charOffset, length: length) }

    var location: ReaderLocation {
        ReaderLocation(chapterIndex: chapterIndex, charOffset: charOffset)
    }
}
