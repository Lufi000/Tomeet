import Foundation

/// 阅读位置：`(章节索引, 章节内字符偏移)`。字符偏移与字号/设备/动态类型无关。
struct ReaderLocation: Sendable, Equatable {
    var chapterIndex: Int
    var charOffset: Int

    init(chapterIndex: Int, charOffset: Int) {
        self.chapterIndex = chapterIndex
        self.charOffset = charOffset
    }

    /// "3:4821" —— 存入 `Book.currentLocation` 的格式。
    var encoded: String { "\(chapterIndex):\(charOffset)" }

    /// 解析 "c:o"。任何非 "#:#" 形态（含负数）返回 nil。
    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let chapter = Int(parts[0]), chapter >= 0,
              let offset = Int(parts[1]), offset >= 0
        else { return nil }
        self.init(chapterIndex: chapter, charOffset: offset)
    }

    /// 按实际章节数与每章字符数夹紧到合法范围（章节数或长度越界时回落）。
    func clamped(chapterCount: Int, chapterLengths: [Int]) -> ReaderLocation {
        guard chapterCount > 0 else { return ReaderLocation(chapterIndex: 0, charOffset: 0) }
        let chapter = min(max(chapterIndex, 0), chapterCount - 1)
        let length = chapter < chapterLengths.count ? chapterLengths[chapter] : 0
        return ReaderLocation(chapterIndex: chapter, charOffset: min(max(charOffset, 0), length))
    }
}
