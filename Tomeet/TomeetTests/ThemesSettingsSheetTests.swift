import SwiftUI
import Testing
@testable import Tomeet

/// 阅读设置面板的控件行必须放得进**最窄的在售机型**。
///
/// 这条测试来自一次真实回归：8pt 疏朗化把三个可点尺寸从 32 提到 48，
/// 一行两个胶囊就从 306pt 涨到 370pt。
/// 402pt 的开发机上还剩 16pt 富余 —— **肉眼完全看不出来**；
/// 375pt 的机器上就两边各裁 8pt。
///
/// 断言读的是 view 自己用的那份 `ControlMetrics`，不是抄来的数字 ——
/// 否则 view 一改，测试就静悄悄地不再保护任何东西。
struct ThemesSettingsSheetTests {
    /// 最窄的在售机型（iPhone SE 3）。面板自身的左右边距要减掉。
    private static let narrowestScreen: CGFloat = 375

    @Test func controlRowFitsTheNarrowestSupportedScreen() {
        let available = Self.narrowestScreen - 2 * Spacing.md
        let needed = ThemesSettingsSheet.ControlMetrics.rowWidth
        #expect(needed <= available,
                "控件行需要 \(needed)pt，最窄机型只剩 \(available)pt")
    }

    /// 防呆：不许把可点尺寸调小来「通过」上一条 ——
    /// 那会把一个裁切问题换成一个够不着的问题。
    @Test func tapTargetsStayAtTheMinimumTouchSize() {
        let target = ThemesSettingsSheet.ControlMetrics.tapTarget
        #expect(target >= 44, "可点尺寸 \(target)pt 低于 44pt 的最小触控尺寸")
    }
}
