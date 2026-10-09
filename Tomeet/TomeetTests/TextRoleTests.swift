import SwiftUI
import Testing
@testable import Tomeet

struct TextRoleTests {
    @Test func rolesMapToExistingThemeColors() {
        #expect(TextRole.pageTitle.color == Theme.ink)
        #expect(TextRole.pageSubtitle.color == Theme.inkSecondary)
        #expect(TextRole.sectionTitle.color == Theme.ink)
        #expect(TextRole.cellTitle.color == Theme.ink)
        #expect(TextRole.body.color == Theme.ink)
        #expect(TextRole.secondary.color == Theme.inkSecondary)
        #expect(TextRole.meta.color == Theme.inkSecondary)
        #expect(TextRole.hint.color == Theme.inkTertiary)
    }

    @Test func onlyTitlesAndButtonsAreBold() {
        let bold: Set<TextRole> = [.pageTitle, .sectionTitle, .cellTitle, .button]
        for role in TextRole.allCases {
            let expected: Font.Weight = bold.contains(role) ? .bold : .regular
            #expect(role.weight == expected, "\(role) 的字重不对")
        }
    }

    @Test func rolesNeverReachForOffScaleTextStyles() {
        // 锁死可用字阶，防止有人往角色里塞 .system(size:) 或冷门 style
        let allowed: Set<Font.TextStyle> = [.largeTitle, .title2, .headline, .body, .subheadline, .caption]
        for role in TextRole.allCases {
            #expect(allowed.contains(role.textStyle),
                    "\(role) 用了刻度外的 TextStyle：\(role.textStyle)")
        }
    }

    @Test func everyRoleHasADefinedColor() {
        for role in TextRole.allCases {
            #expect(role.color != .clear, "\(role) 没有颜色")
        }
    }

    /// 字距从全局常量收进角色后，只有页面大标题该收紧。
    ///
    /// −1.1 是从设计稿抄来的起点（那个值来自 SF Compact Rounded），
    /// 而我们用的是 SF Pro Rounded —— 度量不同，实现时要靠画面对比复核。
    /// 这条测试钉的是**结构**（只有 pageTitle 有字距），不是那个具体数值。
    @Test func onlyPageTitleTightensTracking() {
        #expect(TextRole.pageTitle.tracking == -1.1)
        for role in TextRole.allCases where role != .pageTitle {
            #expect(role.tracking == 0, "\(role) 不该有字距")
        }
    }
}
