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

    static func sortTitle(_ a: Book, _ b: Book) -> Bool {
        a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    static func sortAuthor(_ a: Book, _ b: Book) -> Bool {
        a.author.localizedStandardCompare(b.author) == .orderedAscending
    }

    static func sortRecentlyOpened(_ a: Book, _ b: Book) -> Bool {
        switch (a.lastOpenedDate, b.lastOpenedDate) {
        case let (x?, y?): return x > y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return false
        }
    }

    /// “最近打开”排序别名（plan §Task2 Interfaces 以 `sortRecent` 命名本函数）。
    static func sortRecent(_ a: Book, _ b: Book) -> Bool {
        sortRecentlyOpened(a, b)
    }

    static func sortManual(_ a: Book, _ b: Book) -> Bool {
        a.addedDate < b.addedDate
    }
}