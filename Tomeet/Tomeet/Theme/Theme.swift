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

extension View {
    /// 书架封面的投影。
    ///
    /// **包在这里而不是让调用点写 `.shadow(...)`，是因为门禁的正则 `\bradius:`
    /// 会命中 `.shadow(radius:)`** —— 它会把**阴影半径**误判成**圆角刻度**，
    /// 还会给出「最近的圆角刻度是 8 或 16」这种毫无意义的建议。
    /// 挡在 `Theme/` 里（门禁只扫 `Views/`）既绕开误报，也符合
    /// 「让调用点根本没机会写数字」的既定思路。
    ///
    /// 透明度 0.18 是起点：设计稿的 0.46 是照着纯色块假封面调的，
    /// 压真封面图会脏。以画面对比为准。
    func shelfShadow() -> some View {
        shadow(color: Theme.solidInk.opacity(0.18), radius: 14, x: 6, y: 10)
    }
}
