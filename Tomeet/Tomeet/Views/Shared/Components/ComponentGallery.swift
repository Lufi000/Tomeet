import SwiftUI

/// 设计系统活文档。仅 `#Preview`，不参与 App 运行。
///
/// 改 `Metrics.swift` / `Theme.swift` 任一个值，回到这里就能立刻看到全局效果 ——
/// 比翻 5 个页面快得多。重画某个页面时，也从这里挑组件。
struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                section("TText 文字角色") { textRoles }
                section("TIcon 图标尺寸") { iconRoles }
                section("TButton") { buttons }
                section("TBadge") { badges }
                section("TCard") { cards }
                section("TPageHeader") { pageHeaders }
                section("TEmptyState") { emptyStates }
            }
            .padding(Spacing.md)
        }
        .background(Theme.canvas)
    }

    // MARK: - 分组容器

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .tText(.hint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 各组件

    private var textRoles: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // pageTitle 用竖排三行展示，与首页真实用法一致
            Text("Page\nTitle").tText(.pageTitle)
            Text("Section Title").tText(.sectionTitle)
            Text("Body —— 正文、列表行标题、AI 回复").tText(.body)
            Text("Secondary —— 描述、副标题").tText(.secondary)
            Text("Meta —— 进度、作者").tText(.meta)
            Text("Hint —— 占位符、Thinking").tText(.hint)
            // 颜色逃生门
            Text("Body with color override").tText(.body, color: Theme.accent)
        }
    }

    /// 铁证之四里差 9pt 的那个符号，放在这里一眼比对。
    private var iconRoles: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.badge)
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.control)
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.emphasis)
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.display)
        }
        .foregroundStyle(Theme.ink)
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TButton("Add New Book", style: .primary) {}
            TButton("Import Book", style: .secondary) {}
            HStack(spacing: Spacing.sm) {
                TIconButton(systemName: "arrow.up") {}
                TIconButton(systemName: "arrow.up", isEnabled: false) {}
            }
        }
    }

    private var badges: some View {
        HStack(spacing: Spacing.md) {
            TBadge.text("NEW")
            TBadge.icon("headphones")
        }
    }

    private var cards: some View {
        HStack(spacing: Spacing.sm) {
            Text("Radius.md").tText(.body).padding(Spacing.md).tCard()
            Text("Radius.xl").tText(.body).padding(Spacing.md).tCard(radius: Radius.xl)
        }
    }

    private var pageHeaders: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TPageHeader("Library")
            TPageHeader("I'm\nNow\nReading") {
                Circle()
                    .fill(Theme.sendEnabled)
                    .frame(width: Spacing.xxl, height: Spacing.xxl)
            }
        }
    }

    private var emptyStates: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            TEmptyState(
                illustration: "EmptyStateReading",
                title: "No books yet",
                message: "Import a book and meet the mind inside."
            ) {
                TButton("Import Book", style: .secondary) {}
            }
            TEmptyState(
                illustration: "EmptyStateContinue",
                message: "Books you start reading will appear here."
            )
        }
    }
}

#Preview("Component Gallery") {
    ComponentGallery()
}
