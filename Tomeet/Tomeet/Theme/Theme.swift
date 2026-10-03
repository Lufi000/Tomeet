import SwiftUI

/// Tomeet 主题色板，取自设计稿 "Selection colors"。
///
/// 命名按用途而非色值，方便整 App 逐步套用；改色只改这里。
enum Theme {
    /// 页面背景。
    static let canvas = Color(hex: 0xF8EEE5)
    /// Manta 浅灰:仅首页 + 书籍详情面板,不动全局米色。
    static let homeCanvas = Color(hex: 0xF0F0F3)
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

    /// 全局字距：New York 的字距本就按 UI 尺寸设计，0 即最佳值。
    ///
    /// 保留这个旋钮（而不是删掉各处 `.tracking(Theme.letterSpacing)`）是有意的：
    /// 日后要整体微调，改这一行即可，不必回头补 30 多处调用。
    ///
    /// **为 0 是硬约束**：`Font.book()` 的字号已回到 iOS 标准档，
    /// 此时任何负字距（此前为打字机字体设的 -3.5）都会让字糊成一团。
    static let letterSpacing: Double = 0

    /// 实心填充（主按钮底、用户消息气泡）。比 `ink` 更重，用于需要强对比的实心形状。
    static let solidInk = Color(hex: 0x000000)
    /// 压在 `solidInk` 上的文字与图标。
    static let onSolid = Color(hex: 0xFFFFFF)

    // MARK: 备用色（分隔线、封面点缀、空状态等）

    static let sand = Color(hex: 0xDAC9B9)
    static let sandDeep = Color(hex: 0xDDC7B2)
    static let shell = Color(hex: 0xECDFD3)
    static let cream = Color(hex: 0xFEEFE1)

    // MARK: 阅读器浮层

    /// 阅读设置面板底色。始终是深色 —— 面板压在任意阅读主题之上，
    /// 深色是唯一在 7 套主题下都稳定的选择（Apple Books 同款处理）。
    static let panelSurface = Color(hex: 0x262626)
    /// 浮层上的分隔线与描边。
    static let panelHairline = Color(hex: 0xFFFFFF, opacity: 0.15)
    /// 浮层上的主文字与图标。
    static let panelInk = Color(hex: 0xFFFFFF)
    /// 浮层上的次要文字。
    static let panelInkSecondary = Color(hex: 0xFFFFFF, opacity: 0.6)
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
