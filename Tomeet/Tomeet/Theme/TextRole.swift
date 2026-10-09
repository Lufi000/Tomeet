import SwiftUI

/// 文字角色：字体 + 字距 + 颜色的三元组。
///
/// 抽这个而不是抽字号，是因为字距在各处 `.app(` 里几乎逐一手写重复，
/// 且**永远会被漏写**。打包成角色后，漏写从"可能"变成"不可能"。
enum TextRole: CaseIterable {
    /// 页面大标题。
    case pageTitle
    /// 页面大标题下的引导语。
    case pageSubtitle
    /// 区块标题、空状态标题。
    case sectionTitle
    /// 书架单元里的书名。
    case cellTitle
    /// 正文、列表行标题、AI 回复。
    case body
    /// 描述、副标题、作者。
    case secondary
    /// 进度、作者等元信息。
    case meta
    /// 占位符、Thinking 等提示。
    case hint
    /// 按钮文字。颜色几乎总由调用处覆盖（`.tText(.button, color:)`）。
    case button

    var textStyle: Font.TextStyle {
        switch self {
        case .pageTitle:                   return .largeTitle
        case .pageSubtitle, .sectionTitle: return .title2
        case .cellTitle:                   return .subheadline
        case .button:                      return .headline
        case .body:                        return .body
        case .secondary:                   return .subheadline
        case .meta, .hint:                 return .caption
        }
    }

    var weight: Font.Weight {
        switch self {
        case .pageTitle, .sectionTitle, .cellTitle, .button: return .bold
        case .pageSubtitle, .body, .secondary, .meta, .hint: return .regular
        }
    }

    var color: Color {
        switch self {
        case .pageTitle, .sectionTitle, .cellTitle, .body, .button: return Theme.ink
        case .pageSubtitle, .secondary, .meta:                       return Theme.inkSecondary
        case .hint:                                                  return Theme.inkTertiary
        }
    }

    /// 角色自带的字距。只有页面大标题需要收紧。
    ///
    /// **−1.1 是从设计稿抄的起点，不是结论** —— 那个值来自 SF Compact Rounded，
    /// 而我们用的是 SF Pro Rounded，度量不同。参照：Apple 自己的
    /// Large Title/Emphasized 在 34pt 用 +0.4。以画面对比为准，不要照抄。
    var tracking: Double {
        switch self {
        case .pageTitle: return -1.1
        default:         return 0
        }
    }
}

extension View {
    /// 用法：`.tText(.pageTitle)`
    ///
    /// **字号、字距、字重不可覆盖** —— 那正是角色存在的意义。
    /// 颜色可覆盖（角色默认色不适用时）：`.tText(.button, color: Theme.cream)`
    func tText(_ role: TextRole, color: Color? = nil) -> some View {
        self
            .font(.app(role.textStyle, weight: role.weight))
            .tracking(role.tracking)
            .foregroundStyle(color ?? role.color)
    }
}
