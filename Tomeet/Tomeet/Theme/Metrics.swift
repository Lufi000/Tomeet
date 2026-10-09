import CoreGraphics

/// 间距刻度：**严格 8pt 网格**，七档，没有例外。
///
/// 命名按用途，不按值。数值整体比上一版疏朗一档 ——
/// 页面左右边距 16→24，卡片内衬 12→16。
///
/// 新增档位前先问：现有档位真的不够用吗？大多数"不够用"其实是用错了档。
enum Spacing {
    /// 紧贴的文字堆叠（书名+作者）、图标↔文字。
    static let xs: CGFloat = 8
    /// 标题↔描述、控件内衬。
    static let sm: CGFloat = 16
    /// 页面左右边距、网格列间距、按钮内边距。
    static let md: CGFloat = 24
    /// 内容区顶、区块之间。
    static let lg: CGFloat = 32
    /// 大区块。
    static let xl: CGFloat = 48
    /// 空状态留白。
    static let xxl: CGFloat = 64
    /// 页面级留白、书架网格行间距。
    static let hero: CGFloat = 80

    /// 8 网格**下沿**的半步。
    ///
    /// 唯一用途：角标那类本来就只有十几点高的元素 —— 纵向取整档会让胶囊变成药丸。
    ///
    /// 全 App **仅此一处**次网格值，且必须**具名**：内联的 `Spacing.xs / 2`
    /// 既绕过刻度、也躲开 `MetricsTests`（它只看 `Spacing.all`）。
    /// `DesignSystemGuardTests` 会拦住任何内联的 `Spacing.X / N`。
    static let halfStep: CGFloat = xs / 2

    /// 供门禁测试给出"最近的刻度"建议。
    static let all: [CGFloat] = [xs, sm, md, lg, xl, xxl, hero]
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
