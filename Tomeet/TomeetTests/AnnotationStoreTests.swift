import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct AnnotationStoreTests {

    /// container 必须和 context 一起持有，否则容器被释放、context 变悬垂引用。
    private func makeStore() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        return (container, container.mainContext)
    }

    private let bookID = UUID()

    // MARK: - 书签

    @Test func toggleAddsThenRemovesBookmark() throws {
        let store = try makeStore()
        let location = ReaderLocation(chapterIndex: 2, charOffset: 400)

        let added = try AnnotationStore.toggleBookmark(
            at: location, snippet: "片段", bookID: bookID, in: store.context
        )
        #expect(added)
        #expect(AnnotationStore.bookmarks(for: bookID, in: store.context).count == 1)

        let removed = try AnnotationStore.toggleBookmark(
            at: location, snippet: "片段", bookID: bookID, in: store.context
        )
        #expect(removed == false)
        #expect(AnnotationStore.bookmarks(for: bookID, in: store.context).isEmpty)
    }

    /// 同一页反复加书签不应堆出多条。
    @Test func addingTwiceOnSamePageKeepsOneBookmark() throws {
        let store = try makeStore()
        let location = ReaderLocation(chapterIndex: 0, charOffset: 0)
        try AnnotationStore.addBookmark(at: location, snippet: "a", bookID: bookID, in: store.context)
        try AnnotationStore.addBookmark(at: location, snippet: "a", bookID: bookID, in: store.context)
        #expect(AnnotationStore.bookmarks(for: bookID, in: store.context).count == 1)
    }

    /// 不同页各自成条。
    @Test func differentPagesGetSeparateBookmarks() throws {
        let store = try makeStore()
        try AnnotationStore.addBookmark(
            at: ReaderLocation(chapterIndex: 0, charOffset: 0), snippet: "a", bookID: bookID, in: store.context
        )
        try AnnotationStore.addBookmark(
            at: ReaderLocation(chapterIndex: 0, charOffset: 500), snippet: "b", bookID: bookID, in: store.context
        )
        #expect(AnnotationStore.bookmarks(for: bookID, in: store.context).count == 2)
    }

    /// 书签按章内偏移排序，列表读起来才顺。
    @Test func bookmarksAreOrderedByOffset() throws {
        let store = try makeStore()
        for offset in [900, 100, 500] {
            try AnnotationStore.addBookmark(
                at: ReaderLocation(chapterIndex: 0, charOffset: offset),
                snippet: "s", bookID: bookID, in: store.context
            )
        }
        let offsets = AnnotationStore.bookmarks(for: bookID, in: store.context).map(\.charOffset)
        #expect(offsets == [100, 500, 900])
    }

    // MARK: - 高亮

    @Test func addHighlightStoresRangeAndColor() throws {
        let store = try makeStore()
        let highlight = try #require(try AnnotationStore.addHighlight(
            chapterIndex: 1,
            range: NSRange(location: 120, length: 24),
            color: .blue,
            text: "被高亮的原文",
            bookID: bookID,
            in: store.context
        ))
        #expect(highlight.charOffset == 120)
        #expect(highlight.length == 24)
        #expect(highlight.color == .blue)
        #expect(highlight.range == NSRange(location: 120, length: 24))
    }

    /// 零长度高亮渲染时不可见、也没法长按删除，必须拒绝。
    @Test func zeroLengthHighlightIsRejected() throws {
        let store = try makeStore()
        let result = try AnnotationStore.addHighlight(
            chapterIndex: 0,
            range: NSRange(location: 10, length: 0),
            color: .yellow,
            text: "",
            bookID: bookID,
            in: store.context
        )
        #expect(result == nil)
        #expect(AnnotationStore.highlights(for: bookID, in: store.context).isEmpty)
    }

    @Test func highlightColorCanBeChanged() throws {
        let store = try makeStore()
        let highlight = try #require(try AnnotationStore.addHighlight(
            chapterIndex: 0, range: NSRange(location: 0, length: 5),
            color: .yellow, text: "x", bookID: bookID, in: store.context
        ))
        try AnnotationStore.setColor(.pink, on: highlight, in: store.context)
        let reloaded = try #require(AnnotationStore.highlights(for: bookID, in: store.context).first)
        #expect(reloaded.color == .pink)
    }

    /// 未知的色值不能崩，回退到黄色。
    @Test func unknownColorFallsBackToYellow() {
        let highlight = Highlight(
            bookID: UUID(), chapterIndex: 0, charOffset: 0, length: 1,
            text: "x"
        )
        highlight.colorRaw = "chartreuse"
        #expect(highlight.color == .yellow)
    }

    // MARK: - 按书隔离与对账

    @Test func annotationsAreScopedToTheirBook() throws {
        let store = try makeStore()
        let other = UUID()
        try AnnotationStore.addBookmark(
            at: ReaderLocation(chapterIndex: 0, charOffset: 0), snippet: "a", bookID: bookID, in: store.context
        )
        try AnnotationStore.addBookmark(
            at: ReaderLocation(chapterIndex: 0, charOffset: 0), snippet: "b", bookID: other, in: store.context
        )
        #expect(AnnotationStore.bookmarks(for: bookID, in: store.context).count == 1)
        #expect(AnnotationStore.bookmarks(for: other, in: store.context).count == 1)
    }

    /// 删书要连标注一起清 —— 书签/高亮用 bookID 关联而非 SwiftData 关系，
    /// 不显式对账就会留下永远查不到的孤儿数据。
    @Test func deleteAllRemovesOnlyThatBooksAnnotations() throws {
        let store = try makeStore()
        let other = UUID()
        try AnnotationStore.addBookmark(
            at: ReaderLocation(chapterIndex: 0, charOffset: 0), snippet: "a", bookID: bookID, in: store.context
        )
        try AnnotationStore.addHighlight(
            chapterIndex: 0, range: NSRange(location: 0, length: 3),
            color: .green, text: "x", bookID: bookID, in: store.context
        )
        try AnnotationStore.addBookmark(
            at: ReaderLocation(chapterIndex: 0, charOffset: 0), snippet: "b", bookID: other, in: store.context
        )

        try AnnotationStore.deleteAll(for: bookID, in: store.context)

        #expect(AnnotationStore.bookmarks(for: bookID, in: store.context).isEmpty)
        #expect(AnnotationStore.highlights(for: bookID, in: store.context).isEmpty)
        #expect(AnnotationStore.bookmarks(for: other, in: store.context).count == 1, "别的书的标注不该被误删")
    }

    /// 删书流程要真的把标注带走。
    @Test func deletingBookRemovesItsAnnotations() throws {
        let store = try makeStore()
        let book = Book(title: "书", author: "作者", format: .epub)
        store.context.insert(book)
        try store.context.save()

        try AnnotationStore.addBookmark(
            at: ReaderLocation(chapterIndex: 0, charOffset: 0), snippet: "a", bookID: book.id, in: store.context
        )
        try BookDeletionService.delete(book: book, modelContext: store.context)

        #expect(AnnotationStore.bookmarks(for: book.id, in: store.context).isEmpty)
    }
}
