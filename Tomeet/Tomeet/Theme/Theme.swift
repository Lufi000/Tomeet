import SwiftUI

/// Tomeet 主题色板，取自设计稿 "Selection colors"。
///
/// 命名按用途而非色值，方便整 App 逐步套用；改色只改这里。
enum Theme {
    /// 页面背景。
    static let canvas = Color(hex: 0xF8EEE5)
    /// 卡片底色：上下文卡片、AI 气泡、输入框。
    static let card = Color(hex: 0xFFF9F3)
    /// 用户消息气泡（淡绿）。
    static let userBubble = Color(hex: 0xDDE7CA)

    /// 正文文字（深棕 70%，比纯黑柔和）。
    static let ink = Color(hex: 0x413036, opacity: 0.7)
    /// 次要文字。
    static let inkSecondary = Color.black.opacity(0.5)
    /// 辅助文字 / placeholder / 图标。
    static let inkTertiary = Color.black.opacity(0.3)
    /// 极淡的分隔与禁用态。
    static let inkFaint = Color.black.opacity(0.2)

    /// 发送按钮：可发送底色。
    static let sendEnabled = Color(hex: 0xB5CB8B)
    /// 发送按钮：箭头颜色。
    static let sendArrow = Color(hex: 0xFEFBF7)

    /// 全局强调色：Tab 选中态、徽标、进度文字。
    /// 由 sendEnabled 加深得来，保证在 canvas/card 浅色底上对比度足够。
    static let accent = Color(hex: 0x6F8145)

    /// 阅读进度文字（Continue 卡片右下角）的嫩绿色。
    static let progress = Color(hex: 0x96CB78)

    /// 全局字距基准：Splendid 66 字号放大后默认字距偏松，统一收紧。
    /// 该值按大标题（48pt 基准）标定；请通过 `.splendidTracking(style)` 使用，
    /// 它会按字号比例缩放（小字直接套 -3.5pt 会挤在一起）。
    static let letterSpacing: Double = -3.5

    // MARK: 备用色（分隔线、封面点缀、空状态等）

    static let sand = Color(hex: 0xDAC9B9)
    static let sandDeep = Color(hex: 0xDDC7B2)
    static let shell = Color(hex: 0xECDFD3)
    static let cream = Color(hex: 0xFEEFE1)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
