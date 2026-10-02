import Foundation

extension Book {
    /// mvp.md §3.3：NEW 与百分比进度互斥 —— 仅当 isNew 且零进度时为 NEW。
    var showsNewBadge: Bool {
        isNew && readingProgress == 0
    }

    /// 封面下方的进度文案。NEW 时不显示百分比。
    var progressText: String? {
        guard !showsNewBadge else { return nil }
        return "\(Int((readingProgress * 100).rounded()))%"
    }

    /// 未下载时在封面显示云朵图标（mvp.md §3.2）。
    var needsDownloadIcon: Bool {
        !isDownloaded
    }

    /// 是否配了讲书音频（书架角标与阅读器入口只看它）。
    var hasAudio: Bool {
        audioFileName != nil
    }

    static func sortTitle(_ a: Book, _ b: Book) -> Bool {
        a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    static func sortAuthor(_ a: Book, _ b: Book) -> Bool {
        a.author.localizedStandardCompare(b.author) == .orderedAscending
    }

    /// 最近打开优先；都没打开过（新导入的书）时按加入时间倒序 —— 最新导入的排最前。
    /// 两个 nil 分支原先直接返回 false（等于不排序），新书会落在书架末尾且顺序不稳定。
    static func sortRecentlyOpened(_ a: Book, _ b: Book) -> Bool {
        switch (a.lastOpenedDate, b.lastOpenedDate) {
        case let (x?, y?): return x > y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return sortNewestFirst(a, b)
        }
    }

    /// 手动排序尚未实现，暂以加入时间倒序（最新在前）作为稳定默认。
    static func sortManual(_ a: Book, _ b: Book) -> Bool {
        sortNewestFirst(a, b)
    }

    /// 加入时间倒序，同一时刻时用 id 兜底保证顺序稳定（SwiftUI 需要严格弱序）。
    private static func sortNewestFirst(_ a: Book, _ b: Book) -> Bool {
        if a.addedDate != b.addedDate { return a.addedDate > b.addedDate }
        return a.id.uuidString < b.id.uuidString
    }
}
