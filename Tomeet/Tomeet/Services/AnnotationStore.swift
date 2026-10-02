import Foundation
import SwiftData

/// 书签与高亮的读写入口。
///
/// 与 `BookDeletionService` 同构：纯函数式，接收 `ModelContext`，方便测试里用内存容器驱动。
@MainActor
enum AnnotationStore {

    // MARK: - 查询

    static func bookmarks(for bookID: UUID, in context: ModelContext) -> [Bookmark] {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.bookID == bookID },
            sortBy: [SortDescriptor(\.charOffset)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func highlights(for bookID: UUID, in context: ModelContext) -> [Highlight] {
        let descriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate { $0.bookID == bookID },
            sortBy: [SortDescriptor(\.charOffset)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - 书签

    /// 该页是否已有书签。同一页只允许一个 —— 对应 Apple Books 的点亮/取消。
    static func bookmark(onPageStartingAt location: ReaderLocation, bookID: UUID, in context: ModelContext) -> Bookmark? {
        // 书签锚的是页首字符，所以同一页必然得到同一个 charOffset。
        let chapter = location.chapterIndex
        let offset = location.charOffset
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate {
                $0.bookID == bookID && $0.chapterIndex == chapter && $0.charOffset == offset
            }
        )
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    static func addBookmark(
        at location: ReaderLocation,
        snippet: String,
        bookID: UUID,
        in context: ModelContext
    ) throws -> Bookmark {
        if let existing = bookmark(onPageStartingAt: location, bookID: bookID, in: context) {
            return existing
        }
        let bookmark = Bookmark(
            bookID: bookID,
            chapterIndex: location.chapterIndex,
            charOffset: location.charOffset,
            snippet: snippet
        )
        context.insert(bookmark)
        try context.save()
        return bookmark
    }

    /// 切换当前页的书签状态。返回切换后是否处于「已加书签」。
    @discardableResult
    static func toggleBookmark(
        at location: ReaderLocation,
        snippet: String,
        bookID: UUID,
        in context: ModelContext
    ) throws -> Bool {
        if let existing = bookmark(onPageStartingAt: location, bookID: bookID, in: context) {
            context.delete(existing)
            try context.save()
            return false
        }
        try addBookmark(at: location, snippet: snippet, bookID: bookID, in: context)
        return true
    }

    static func remove(_ bookmark: Bookmark, in context: ModelContext) throws {
        context.delete(bookmark)
        try context.save()
    }

    // MARK: - 高亮

    /// 高亮必须覆盖至少一个字符，否则渲染时不可见、也没法长按删除。
    static func canHighlight(_ range: NSRange) -> Bool {
        range.length > 0
    }

    @discardableResult
    static func addHighlight(
        chapterIndex: Int,
        range: NSRange,
        color: HighlightColor,
        text: String,
        bookID: UUID,
        in context: ModelContext
    ) throws -> Highlight? {
        guard canHighlight(range) else { return nil }
        let highlight = Highlight(
            bookID: bookID,
            chapterIndex: chapterIndex,
            charOffset: range.location,
            length: range.length,
            color: color,
            text: text
        )
        context.insert(highlight)
        try context.save()
        return highlight
    }

    static func setColor(_ color: HighlightColor, on highlight: Highlight, in context: ModelContext) throws {
        highlight.color = color
        try context.save()
    }

    static func remove(_ highlight: Highlight, in context: ModelContext) throws {
        context.delete(highlight)
        try context.save()
    }

    // MARK: - 对账

    /// 删书时清掉它的书签与高亮。书用 `Book.id` 关联而非 SwiftData 关系，
    /// 所以必须显式对账，否则会留下永远查不到的孤儿数据。
    static func deleteAll(for bookID: UUID, in context: ModelContext) throws {
        for bookmark in bookmarks(for: bookID, in: context) {
            context.delete(bookmark)
        }
        for highlight in highlights(for: bookID, in: context) {
            context.delete(highlight)
        }
        try context.save()
    }
}
