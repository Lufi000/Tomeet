import Foundation
import SwiftData
import Testing
@testable import Tomeet

/// 书架排序与导入去重。
///
/// 回归自 bug.md：「添加书籍顺序问题 最后添加的应该在最前面 且现在可以重复添加」。
@MainActor
struct LibraryOrderingTests {

    private func book(
        title: String,
        author: String = "A",
        added: TimeInterval,
        opened: TimeInterval? = nil
    ) -> Book {
        let reference = Date(timeIntervalSince1970: 1_000_000)
        return Book(
            title: title,
            author: author,
            format: .epub,
            addedDate: reference.addingTimeInterval(added),
            lastOpenedDate: opened.map { reference.addingTimeInterval($0) }
        )
    }

    // MARK: - 排序

    /// 都没打开过的书（刚导入）按加入时间倒序：最后添加的排最前。
    @Test func unopenedBooksSortNewestFirst() {
        let oldest = book(title: "Old", added: 0)
        let newest = book(title: "New", added: 100)
        #expect(Book.sortRecentlyOpened(newest, oldest) == true)
        #expect(Book.sortRecentlyOpened(oldest, newest) == false)
    }

    /// 打开过的书永远排在没打开过的前面（最近在读优先）。
    @Test func openedBooksOutrankUnopened() {
        let opened = book(title: "Opened", added: 0, opened: 0)
        let fresh = book(title: "Fresh", added: 999)
        #expect(Book.sortRecentlyOpened(opened, fresh) == true)
        #expect(Book.sortRecentlyOpened(fresh, opened) == false)
    }

    /// 都打开过：更晚打开的在前。
    @Test func mostRecentlyOpenedComesFirst() {
        let earlier = book(title: "Earlier", added: 0, opened: 10)
        let later = book(title: "Later", added: 0, opened: 20)
        #expect(Book.sortRecentlyOpened(later, earlier) == true)
        #expect(Book.sortRecentlyOpened(earlier, later) == false)
    }

    /// Manual 目前没有真正的手动顺序，以加入时间倒序兜底 —— 最新在前。
    @Test func manualSortIsNewestFirst() {
        let older = book(title: "Older", added: 0)
        let newer = book(title: "Newer", added: 50)
        #expect(Book.sortManual(newer, older) == true)
        #expect(Book.sortManual(older, newer) == false)
    }

    /// 加入时间完全相同时（批量导入）也必须是严格弱序，否则 SwiftUI 列表顺序会抖动。
    @Test func identicalAddedDateIsStable() {
        let a = book(title: "A", added: 7)
        let b = book(title: "B", added: 7)
        #expect(Book.sortManual(a, b) != Book.sortManual(b, a))
        #expect(Book.sortRecentlyOpened(a, b) != Book.sortRecentlyOpened(b, a))
    }

    // MARK: - 去重

    /// 必须把 container 一起返回：`mainContext` 由 container 持有，
    /// 只返回 context 的话容器会在函数返回时被释放，context 变悬垂引用 —— 测试会直接崩。
    private func makeStore() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        return (container, container.mainContext)
    }

    @Test func duplicateDetectedBySameTitleAndAuthor() throws {
        let store = try makeStore()
        let context = store.context
        context.insert(Book(title: "复杂", author: "梅拉妮·米歇尔", format: .epub))
        let existing = try #require(BookImporter.duplicateTitle(
            for: .init(title: "复杂", author: "梅拉妮·米歇尔"),
            in: context
        ))
        #expect(existing == "复杂")
    }

    /// 大量 EPUB 没有 dc:creator。第一次导入有作者、第二次没有，仍应认成同一本。
    @Test func duplicateDetectedWhenEitherAuthorIsBlank() throws {
        let store = try makeStore()
        let context = store.context
        context.insert(Book(title: "复杂", author: "梅拉妮·米歇尔", format: .epub))
        let missingAuthor = BookImporter.duplicateTitle(for: .init(title: "复杂", author: ""), in: context)
        #expect(missingAuthor == "复杂")
    }

    /// 大小写、全角空格、多余空白都不应造成重复漏判。
    @Test func duplicateIgnoresCaseAndWhitespace() throws {
        let store = try makeStore()
        let context = store.context
        context.insert(Book(title: "The   Green　Mummy", author: "Fergus Hume", format: .epub))
        let matched = BookImporter.duplicateTitle(
            for: .init(title: "the green mummy", author: "fergus hume"),
            in: context
        )
        #expect(matched != nil)
    }

    @Test func differentBooksAreNotDuplicates() throws {
        let store = try makeStore()
        let context = store.context
        context.insert(Book(title: "复杂", author: "梅拉妮·米歇尔", format: .epub))
        let other = BookImporter.duplicateTitle(
            for: .init(title: "重来也不会好过现在", author: "基兰·塞蒂亚"),
            in: context
        )
        #expect(other == nil)
    }

    /// 同名但作者明确不同 —— 是两本不同的书，不该拦。
    @Test func sameTitleDifferentExplicitAuthorsAreDistinct() throws {
        let store = try makeStore()
        let context = store.context
        context.insert(Book(title: "导读", author: "甲", format: .epub))
        let other = BookImporter.duplicateTitle(for: .init(title: "导读", author: "乙"), in: context)
        #expect(other == nil)
    }

    @Test func emptyTitleIsNeverADuplicate() throws {
        let store = try makeStore()
        let context = store.context
        context.insert(Book(title: "", author: "", format: .epub))
        let other = BookImporter.duplicateTitle(for: .init(title: "   ", author: ""), in: context)
        #expect(other == nil)
    }
}
