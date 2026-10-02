import SwiftUI

/// 全 App 统一的文字按钮。
///
/// 吸收原先散落各处的三种写法 —— 同样是「导入一本书」，
/// `HomeView` 是黑填充胶囊、`LibraryView` 是 accent 描边胶囊，长得完全不同。
struct TButton: View {
    enum Style {
        /// 黑填充胶囊 + cream 文字。页面主行动（如「Add New Book」）。
        case primary
        /// accent 描边胶囊 + accent 文字。次级行动（如「Import Book」）。
        case secondary
    }

    private let title: String
    private let style: Style
    private let action: () -> Void

    init(_ title: String, style: Style, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .tText(.button, color: foreground)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(background)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary:   return Theme.cream
        case .secondary: return Theme.accent
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            Capsule().fill(Theme.solidInk)
        case .secondary:
            Capsule().stroke(Theme.accent, lineWidth: 1.5)
        }
    }
}

/// 圆形图标按钮。目前唯一使用者是聊天输入条的发送键。
struct TIconButton: View {
    private let systemName: String
    private let isEnabled: Bool
    private let action: () -> Void

    init(systemName: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.systemName = systemName
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .tIcon(.body, weight: .bold)
                .foregroundStyle(isEnabled ? Theme.onSolid : Theme.inkTertiary)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(
                    Circle().fill(isEnabled ? Theme.solidInk : Theme.inkFaint)
                )
        }
        .disabled(!isEnabled)
    }
}
