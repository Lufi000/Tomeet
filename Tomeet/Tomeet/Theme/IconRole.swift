import SwiftUI

/// 图标尺寸的推荐档位。**这不是限制** —— 直接传任意 `Font.TextStyle` 同样合法。
///
/// 不做成 enum 硬限制是有意的：SF Symbols 本就按文字字阶设计，
/// 硬塞一个更小的枚举只会逼出新的魔法数字。
enum IconRole {
    /// 角标（`headphones` / `icloud`）。
    static let badge: Font.TextStyle = .caption
    /// 工具条、按钮内图标（`ellipsis.circle` / `arrow.up`）。
    static let control: Font.TextStyle = .body
    /// 次级操作、关闭键。
    static let emphasis: Font.TextStyle = .title2
    /// 主操作（全屏播放键）。
    static let display: Font.TextStyle = .largeTitle

    /// 画廊按这个顺序渲染。
    static let recommended: [Font.TextStyle] = [badge, control, emphasis, display]
}

extension View {
    /// 图标尺寸角色。用法：`.tIcon(.control)`
    ///
    /// 走语义 `TextStyle`（而非 `CGFloat`）以自动获得 Dynamic Type 支持。
    /// 字形风格固定为系统默认 SF Pro —— 文字是 `Font.book()` 的衬线（New York），
    /// 而 SF Symbols 没有衬线变体。给图标挂 `.font(.book(...))` 只会落到回退字形，
    /// 所以这里刻意不跟随文字字体；`DesignSystemGuardTests` 会拦住这种写法。
    func tIcon(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        self.font(.system(style, weight: weight))
    }
}
