import Foundation
import Testing
@testable import Tomeet

/// 自动夜间主题与行距预设。
struct ReaderSettingsTests {

    // MARK: - 自动夜间

    @Test func manualThemeIgnoresSystemAppearance() {
        let settings = ReaderSettings(theme: .calm, autoNightTheme: false)
        #expect(settings.resolvedTheme(isDarkAppearance: false) == .calm)
        #expect(settings.resolvedTheme(isDarkAppearance: true) == .calm)
    }

    @Test func autoNightPicksThemeByAppearance() {
        let settings = ReaderSettings(
            autoNightTheme: true,
            lightTheme: .paper,
            darkTheme: .ink
        )
        #expect(settings.resolvedTheme(isDarkAppearance: false) == .paper)
        #expect(settings.resolvedTheme(isDarkAppearance: true) == .ink)
    }

    /// 自动夜间开启时点选主题，只改**当前外观**那一套，不能把另一套也顺手改掉。
    @Test func selectingThemeOnlyTouchesCurrentAppearanceSlot() {
        let settings = ReaderSettings(
            autoNightTheme: true,
            lightTheme: .paper,
            darkTheme: .ink
        )
        settings.setTheme(.focus, isDarkAppearance: true)
        #expect(settings.darkTheme == .focus)
        #expect(settings.lightTheme == .paper, "白天用的那套不该被动到")

        settings.setTheme(.calm, isDarkAppearance: false)
        #expect(settings.lightTheme == .calm)
        #expect(settings.darkTheme == .focus, "夜里用的那套不该被动到")
    }

    /// 自动夜间关闭时，点选主题写进唯一的 theme 字段。
    @Test func selectingThemeWithoutAutoNightWritesTheSingleTheme() {
        let settings = ReaderSettings(theme: .paper, autoNightTheme: false)
        settings.setTheme(.bold, isDarkAppearance: true)
        #expect(settings.theme == .bold)
    }

    @Test func selectedThemeFollowsAppearanceWhenAutoNightIsOn() {
        let settings = ReaderSettings(autoNightTheme: true, lightTheme: .paper, darkTheme: .bold)
        #expect(settings.selectedTheme(isDarkAppearance: false) == .paper)
        #expect(settings.selectedTheme(isDarkAppearance: true) == .bold)
    }

    // MARK: - 行距预设

    @Test func applyingPresetUpdatesAllThreeValues() {
        let settings = ReaderSettings()
        settings.apply(.loose)
        #expect(settings.lineSpacing == SpacingPreset.loose.lineSpacing)
        #expect(settings.paragraphSpacing == SpacingPreset.loose.paragraphSpacing)
        #expect(settings.lineHeightMultiple == SpacingPreset.loose.lineHeightMultiple)
    }

    /// 默认值应当落在 Normal 档，否则打开面板会看不到任何选中项。
    @Test func defaultsSnapToNormalPreset() {
        #expect(ReaderSettings().spacingPreset == .normal)
    }

    @Test func eachPresetRoundTrips() {
        for preset in SpacingPreset.allCases {
            let settings = ReaderSettings()
            settings.apply(preset)
            #expect(settings.spacingPreset == preset, "\(preset) 应用后应能反查回自己")
        }
    }

    /// 用户手调的中间值要能归到最近的一档，而不是崩或乱跳。
    @Test func intermediateValuesSnapToNearestPreset() {
        let settings = ReaderSettings()
        settings.lineSpacing = 9
        settings.paragraphSpacing = 13
        settings.lineHeightMultiple = 1.5
        #expect(settings.spacingPreset == .normal)
    }

    @Test func allPresetsAreDistinct() {
        let signatures = Set(SpacingPreset.allCases.map {
            "\($0.lineSpacing)-\($0.paragraphSpacing)-\($0.lineHeightMultiple)"
        })
        #expect(signatures.count == SpacingPreset.allCases.count)
    }
}
