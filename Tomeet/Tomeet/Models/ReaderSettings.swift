import Foundation
import SwiftData

/// 全局阅读设置。以 SwiftData 单例形式持久化，供所有书籍共用。
@Model
final class ReaderSettings {
    /// `ReaderTheme.rawValue`。
    var themeRawValue: String

    /// 相对基准字号 17 的偏移量。允许范围 [-4, 6]，步长 1。
    var fontSizeOffset: Double

    /// 行距，默认 8。
    var lineSpacing: Double

    /// 亮度 0...1；0.5 为默认值。
    var brightness: Double

    /// 用户是否主动调整过亮度。false 时进入阅读器不覆盖系统亮度。
    var hasCustomBrightness: Bool

    init(
        theme: ReaderTheme = .original,
        fontSizeOffset: Double = 0,
        lineSpacing: Double = 8,
        brightness: Double = 0.5,
        hasCustomBrightness: Bool = false
    ) {
        self.themeRawValue = theme.rawValue
        self.fontSizeOffset = fontSizeOffset
        self.lineSpacing = lineSpacing
        self.brightness = brightness
        self.hasCustomBrightness = hasCustomBrightness
    }

    /// 当前主题。若持久化值异常则回退到 `.original`。
    var theme: ReaderTheme {
        get { ReaderTheme(rawValue: themeRawValue) ?? .original }
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
            return existing
        }
        let settings = ReaderSettings()
        context.insert(settings)
        return settings
    }
}
