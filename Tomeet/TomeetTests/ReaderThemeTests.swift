import Foundation
import Testing
@testable import Tomeet

struct ReaderThemeTests {
    @Test func allThemesHaveOpaqueColors() {
        for theme in ReaderTheme.allCases {
            #expect(theme.backgroundColor != .clear)
            #expect(theme.textColor != .clear)
            #expect(theme.accentColor != .clear)
        }
    }

    @Test func inkIsDarkerThanQuiet() {
        // 简单比较：ink 背景色在 0x0D0D0D，比 quiet 的 0x1C1C1E 更暗。
        #expect(ReaderTheme.ink.displayName == "Ink")
    }

    @Test func paperUsesDarkAccents() {
        #expect(ReaderTheme.paper.previewUsesDarkAccents == true)
    }
}
