import SwiftUI

/// 页面大标题（可带引导语）。
///
/// 吸收原先在 `LibraryView` 里被三条代码路径各抄一遍的 `libraryHeader`，
/// 以及 `HomeView.swift:83` 的变体。
///
/// `subtitle` 有默认值，现有调用点不受影响。
struct TPageHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).tText(.pageTitle)
                if let subtitle {
                    Text(subtitle).tText(.pageSubtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

extension TPageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}
