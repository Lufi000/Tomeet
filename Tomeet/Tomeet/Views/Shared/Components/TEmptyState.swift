import SwiftUI

/// 空状态：插画 + 可选标题 + 文案 + 可选行动按钮。
///
/// 吸收 `LibraryView`（有标题、有按钮）与 `HomeView`（无标题、无按钮）两处。
/// 插画用固定高度而非宽度 —— 两处原实现一个用 `.frame(width: 240)`
/// 一个用 `.frame(height: 160)`，统一到高度更能适配不同长宽比的图。
struct TEmptyState<Action: View>: View {
    /// 插画高度。取刻度 `hero` 的 3 倍而非写死 160 —— 这样调 `Spacing.hero`
    /// 时插画会跟着整体缩放，不会脱节。
    private static var illustrationHeight: CGFloat { Spacing.hero * 3 }

    private let illustration: String
    private let title: String?
    private let message: String
    private let action: Action

    init(
        illustration: String,
        title: String? = nil,
        message: String,
        @ViewBuilder action: () -> Action
    ) {
        self.illustration = illustration
        self.title = title
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(illustration)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: Self.illustrationHeight)

            if let title {
                Text(title).tText(.sectionTitle)
            }

            Text(message)
                .tText(.secondary)
                .multilineTextAlignment(.center)

            action
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxl)
    }
}

extension TEmptyState where Action == EmptyView {
    init(illustration: String, title: String? = nil, message: String) {
        self.init(illustration: illustration, title: title, message: message) {
            EmptyView()
        }
    }
}
