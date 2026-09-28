import CoreGraphics

/// 间距刻度：4pt 网格。命名按用途，不按值。
///
/// 新增档位前先问：现有档位真的不够用吗？大多数"不够用"其实是用错了档。
enum Spacing {
    /// 仅用于**紧贴的文字堆叠**（书名+作者、标题+副标题）。
    /// 这是刻度里唯一的非 4 倍数，是显式的受控例外，不是漏网之鱼。
    static let hairline: CGFloat = 2
    /// 图标↔文字、紧凑内衬。
    static let xs: CGFloat = 4
    /// 标题↔描述、网格行间距。
    static let sm: CGFloat = 8
    /// 列表行内元素、按钮内边距。
    static let md: CGFloat = 12
    /// 主力：页面左右边距、网格列间距。
    static let lg: CGFloat = 16
    /// 区块之间。
    static let xl: CGFloat = 24
    /// 大区块、空状态留白。
    static let xxl: CGFloat = 32
    /// 页面级英雄留白。
    static let hero: CGFloat = 48

    /// 供门禁测试给出"最近的刻度"建议。
    static let all: [CGFloat] = [hairline, xs, sm, md, lg, xl, xxl, hero]
}

/// 圆角刻度。**始终配合 `style: .continuous` 使用** —— iOS 系统形状是 squircle，
/// SwiftUI 默认的 `.circular` 不是。
enum Radius {
    /// 缩略图、小标签。
    static let sm: CGFloat = 8
    /// 卡片、输入框、列表行。
    static let md: CGFloat = 12
    /// 气泡、大卡片。
    static let lg: CGFloat = 16
    /// 近全屏面板。
    static let xl: CGFloat = 24

    static let all: [CGFloat] = [sm, md, lg, xl]
}
