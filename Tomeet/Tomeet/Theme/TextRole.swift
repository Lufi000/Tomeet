import SwiftUI

/// 文字角色：字体 + 字距 + 颜色的三元组。
///
/// 抽这个而不是抽字号，是因为 `.tracking(Theme.letterSpacing)` 在几十处
/// `.book(` 里几乎逐一手写重复，且**永远会被漏写**。
/// 打包成角色后，漏写从"可能"变成"不可能"。
enum TextRole: CaseIterable {
    /// 页面大标题。
    case pageTitle
    /// 区块标题、空状态标题。
    case sectionTitle
    /// 正文、列表行标题、AI 回复。
    case body
    /// 描述、副标题。
    case secondary
    /// 进度、作者等元信息。
    case meta
    /// 占位符、Thinking 等提示。
    case hint
    /// 按钮文字。颜色几乎总由调用处覆盖（`.tText(.button, color:)`）。
    case button

    var textStyle: Font.TextStyle {
        switch self {
        case .pageTitle:    return .largeTitle
        case .sectionTitle: return .title2
        case .button:       return .headline
        case .body:         return .body
        case .secondary:    return .subheadline
        case .meta, .hint:  return .caption
        }
    }

    var weight: Font.Weight {
        switch self {
        case .pageTitle, .sectionTitle, .button: return .bold
        case .body, .secondary, .meta, .hint:    return .regular
        }
    }

    var color: Color {
        switch self {
        case .pageTitle, .sectionTitle, .body, .button: return Theme.ink
        case .secondary, .meta:                         return Theme.inkSecondary
        case .hint:                                     return Theme.inkTertiary
        }
    }
}

extension View {
    /// 用法：`.tText(.pageTitle)`
    ///
    /// **字号与字距不可覆盖** —— 那正是角色存在的意义。
    /// 颜色可覆盖（角色默认色不适用时）：`.tText(.button, color: Theme.cream)`
    func tText(_ role: TextRole, color: Color? = nil) -> some View {
        self
            .font(.book(role.textStyle, weight: role.weight))
            .tracking(Theme.letterSpacing)
            .foregroundStyle(color ?? role.color)
    }
}
