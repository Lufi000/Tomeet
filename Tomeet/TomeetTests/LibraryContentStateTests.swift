import Testing
@testable import Tomeet

/// 「搜/筛之后一条都没有」时该显示什么。
///
/// 这条测试来自一次真实漏网：空结果提示原先只挂在**网格**那条路径上，
/// 切到列表模式或「按主题」分组再搜索就会白屏 —— 而 spec §5.5 明确写着
/// 「无结果 → 一句空态提示，不是空白」。
///
/// `LibraryView.body` 现在只用 `hasNothingToShow` 这一个判断点，
/// 所以三条路径不可能再分叉。
struct LibraryContentStateTests {
    @Test func everyContentPathReportsEmptyResults() {
        // 网格与列表（不分组）
        #expect(LibraryView.hasNothingToShow(
            visibleCount: 0, themeSectionCount: 0, groupByTheme: false
        ), "网格/列表路径搜不到结果时应当显示提示，而不是空白")

        // 按主题分组 —— 就是原先会白屏的那条
        #expect(LibraryView.hasNothingToShow(
            visibleCount: 0, themeSectionCount: 0, groupByTheme: true
        ), "按主题分组搜不到结果时应当显示提示，而不是空白")
    }

    @Test func resultsAreNotReportedAsEmpty() {
        #expect(!LibraryView.hasNothingToShow(
            visibleCount: 3, themeSectionCount: 1, groupByTheme: false
        ))
        #expect(!LibraryView.hasNothingToShow(
            visibleCount: 3, themeSectionCount: 1, groupByTheme: true
        ))
    }

    /// 分组时看的是**分组数**，不是书数 —— 有书但一个主题都没命中，同样是空。
    @Test func groupingIsJudgedBySectionsNotByBookCount() {
        #expect(LibraryView.hasNothingToShow(
            visibleCount: 3, themeSectionCount: 0, groupByTheme: true
        ), "分组模式下有书但没有任何主题命中，应当算空")
    }
}
