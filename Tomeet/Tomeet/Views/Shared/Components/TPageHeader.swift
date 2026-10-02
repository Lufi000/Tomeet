import SwiftUI

/// 页面大标题。吸收原先在 `LibraryView` 里被三条代码路径各抄一遍的 `libraryHeader`，
/// 以及 `HomeView.swift:83` 的变体。
struct TPageHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .tText(.pageTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }
}

extension TPageHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}
