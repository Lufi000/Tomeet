import SwiftUI

/// 角标。吸收 `BookGridCell` 里内边距不一致的两处（6/2 与 5）。
struct TBadge: View {
    private enum Kind {
        case text(String)
        case icon(String)
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    /// accent 胶囊文字角标，如封面左上角的「NEW」。
    static func text(_ text: String) -> TBadge {
        TBadge(kind: .text(text))
    }

    /// 深色半透明圆图标角标，如封面右上角的耳机。
    static func icon(_ systemName: String) -> TBadge {
        TBadge(kind: .icon(systemName))
    }

    var body: some View {
        switch kind {
        case .text(let text):
            Text(text)
                .tText(.hint, color: Theme.onSolid)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.hairline)
                .background(Capsule().fill(Theme.accent))
                .padding(Spacing.sm)

        case .icon(let systemName):
            Image(systemName: systemName)
                .tIcon(.caption, weight: .semibold)
                .foregroundStyle(Theme.onSolid)
                .padding(Spacing.xs)
                .background(Circle().fill(Theme.solidInk.opacity(0.65)))
                .padding(Spacing.sm)
        }
    }
}
