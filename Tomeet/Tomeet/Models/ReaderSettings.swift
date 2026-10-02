import Foundation
import SwiftData

/// 行距/段距三档预设。
///
/// 替代原来的裸滑块：对普通读者来说「行距 8 还是 9」没有意义，
/// 「紧 / 标准 / 松」才是能一眼做决定的选项（Apple Books 也是三档）。
enum SpacingPreset: String, CaseIterable, Identifiable, Sendable {
    case tight
    case normal
    case loose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tight: "Tight"
        case .normal: "Normal"
        case .loose: "Loose"
        }
    }

    var lineSpacing: Double {
        switch self {
        case .tight: 4
        case .normal: 8
        case .loose: 12
        }
    }

    var paragraphSpacing: Double {
        switch self {
        case .tight: 6
        case .normal: 12
        case .loose: 20
        }
    }

    var lineHeightMultiple: Double {
        switch self {
        case .tight: 1.35
        case .normal: 1.55
        case .loose: 1.75
        }
    }
}

/// 全局阅读设置。以 SwiftData 单例形式持久化，供所有书籍共用。
@Model
final class ReaderSettings {
    /// `ReaderTheme.rawValue`。
    var themeRawValue: String

    /// 相对基准字号 17 的偏移量。允许范围 [-4, 6]，步长 1。
    var fontSizeOffset: Double

    /// 行距，默认 8。
    var lineSpacing: Double

    /// 段间距，默认 12。
    var paragraphSpacing: Double = 12

    /// 首行缩进（em），默认 2.0。
    var firstLineIndent: Double = 2.0

    /// 行高倍数，默认 1.55。
    var lineHeightMultiple: Double = 1.55

    /// 水平边距，默认 28。
    var horizontalMargin: Double = 28

    /// 垂直边距，默认 36。
    var verticalMargin: Double = 36

    /// 亮度 0...1；0.5 为默认值。
    var brightness: Double

    /// 用户是否主动调整过亮度。false 时进入阅读器不覆盖系统亮度。
    var hasCustomBrightness: Bool

    /// 自动夜间主题：跟随系统外观在浅色/深色主题间切换（Apple Books 的那个半圆图标）。
    var autoNightTheme: Bool = false

    /// 自动夜间开启时，浅色外观用哪套主题。
    var lightThemeRawValue: String = ReaderTheme.paper.rawValue

    /// 自动夜间开启时，深色外观用哪套主题。
    var darkThemeRawValue: String = ReaderTheme.ink.rawValue

    init(
        theme: ReaderTheme = .paper,
        fontSizeOffset: Double = 0,
        lineSpacing: Double = 8,
        paragraphSpacing: Double = 12,
        firstLineIndent: Double = 2.0,
        lineHeightMultiple: Double = 1.55,
        horizontalMargin: Double = 28,
        verticalMargin: Double = 36,
        brightness: Double = 0.5,
        hasCustomBrightness: Bool = false,
        autoNightTheme: Bool = false,
        lightTheme: ReaderTheme = .paper,
        darkTheme: ReaderTheme = .ink
    ) {
        self.themeRawValue = theme.rawValue
        self.fontSizeOffset = fontSizeOffset
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.firstLineIndent = firstLineIndent
        self.lineHeightMultiple = lineHeightMultiple
        self.horizontalMargin = horizontalMargin
        self.verticalMargin = verticalMargin
        self.brightness = brightness
        self.hasCustomBrightness = hasCustomBrightness
        self.autoNightTheme = autoNightTheme
        self.lightThemeRawValue = lightTheme.rawValue
        self.darkThemeRawValue = darkTheme.rawValue
    }

    // MARK: - 主题

    /// 自动夜间开启时用的浅色主题。
    var lightTheme: ReaderTheme {
        get { ReaderTheme(rawValue: lightThemeRawValue) ?? .paper }
        set { lightThemeRawValue = newValue.rawValue }
    }

    /// 自动夜间开启时用的深色主题。
    var darkTheme: ReaderTheme {
        get { ReaderTheme(rawValue: darkThemeRawValue) ?? .ink }
        set { darkThemeRawValue = newValue.rawValue }
    }

    /// 按当前外观解析出真正生效的主题。
    /// 自动夜间关闭时就是用户直接选的那套；开启时按系统深浅色取对应的一套。
    func resolvedTheme(isDarkAppearance: Bool) -> ReaderTheme {
        guard autoNightTheme else { return theme }
        return isDarkAppearance ? darkTheme : lightTheme
    }

    /// 用户此刻在主题网格里点某套主题时，应该写进哪个字段。
    /// 自动夜间开启时写的是"当前外观对应的一套"，所以白天点选不会把夜间主题也改掉。
    func setTheme(_ newTheme: ReaderTheme, isDarkAppearance: Bool) {
        if autoNightTheme, isDarkAppearance {
            darkTheme = newTheme
        } else if autoNightTheme {
            lightTheme = newTheme
        } else {
            theme = newTheme
        }
    }

    /// 当前外观下网格里高亮显示的那一套。
    func selectedTheme(isDarkAppearance: Bool) -> ReaderTheme {
        autoNightTheme ? (isDarkAppearance ? darkTheme : lightTheme) : theme
    }

    // MARK: - 行距/段距

    /// 当前值最接近哪一档。用于在分段控件里高亮。
    var spacingPreset: SpacingPreset {
        let current = (lineSpacing, paragraphSpacing, lineHeightMultiple)
        return SpacingPreset.allCases.min { lhs, rhs in
            Self.distance(from: current, to: lhs) < Self.distance(from: current, to: rhs)
        } ?? .normal
    }

    func apply(_ preset: SpacingPreset) {
        lineSpacing = preset.lineSpacing
        paragraphSpacing = preset.paragraphSpacing
        lineHeightMultiple = preset.lineHeightMultiple
    }

    private static func distance(
        from current: (Double, Double, Double),
        to preset: SpacingPreset
    ) -> Double {
        abs(current.0 - preset.lineSpacing)
            + abs(current.1 - preset.paragraphSpacing)
            + abs(current.2 - preset.lineHeightMultiple) * 10
    }

    /// 当前主题。若持久化值异常则回退到 `.paper`（全 App 米色主题）。
    var theme: ReaderTheme {
        get { ReaderTheme(rawValue: themeRawValue) ?? .paper }
        set { themeRawValue = newValue.rawValue }
    }

    /// 实际字号 = 基准 17 + 偏移量。
    var fontSize: CGFloat {
        CGFloat(17 + fontSizeOffset)
    }

    /// 从 ModelContext 读取全局设置；不存在时创建并插入。
    static func fetchOrCreate(in context: ModelContext) -> ReaderSettings {
        let descriptor = FetchDescriptor<ReaderSettings>()
        if let existing = try? context.fetch(descriptor).first {
            // 一次性迁移：旧默认纯黑 Original → 全 App 米色 Paper。
            // 区分不了"默认继承"还是"主动选择"，统一按产品决策收敛到 App 配色。
            if existing.theme == .original {
                existing.theme = .paper
                try? context.save()
            }
            return existing
        }
        let settings = ReaderSettings()
        context.insert(settings)
        return settings
    }
}
