import Foundation
import Testing
@testable import Tomeet

struct ReaderViewTests {
    /// Contents 菜单的数据源函数：真实章节标题列表 + 固定占位行（与占位页视觉一致）。
    @Test func contentsRowsCombineChaptersAndPlaceholders() {
        let chapters = [
            Chapter(id: "c0", title: "Chapter One", blocks: [.heading(level: 1, text: "H")]),
            Chapter(id: "c1", title: "Chapter Two", blocks: []),
        ]
        let rows = ReaderView.contentsRows(chapters: chapters)
        #expect(rows.count == 2 + ReaderView.placeholderMenuRowCount)
        #expect(rows.prefix(2).map(\.title) == ["Chapter One", "Chapter Two"])
        // 章节行可跳转（真实 chapter reference）；占位行不可跳转。
        #expect(rows[0].jumpable)
        #expect(rows[2].jumpable == false)
    }
}
