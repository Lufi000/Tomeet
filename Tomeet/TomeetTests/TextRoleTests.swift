import SwiftUI
import Testing
@testable import Tomeet

struct TextRoleTests {
    @Test func rolesMapToExistingThemeColors() {
        #expect(TextRole.pageTitle.color == Theme.ink)
        #expect(TextRole.sectionTitle.color == Theme.ink)
        #expect(TextRole.body.color == Theme.ink)
        #expect(TextRole.secondary.color == Theme.inkSecondary)
        #expect(TextRole.meta.color == Theme.inkSecondary)
        #expect(TextRole.hint.color == Theme.inkTertiary)
    }

    @Test func onlyTitlesAndButtonsAreBold() {
        let bold: Set<TextRole> = [.pageTitle, .sectionTitle, .button]
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
}
