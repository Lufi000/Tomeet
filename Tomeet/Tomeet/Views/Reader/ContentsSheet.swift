import SwiftUI

/// 阅读器目录面板：目录 / 书签 / 高亮 三个 tab，均可点击跳回原位。
/// 布局对齐 Apple Books 的 Contents 面板（封面 + 书名 + 页码 + 自定义标题栏）。
struct ContentsSheet: View {
    let book: Book
    let viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable, Identifiable {
        case contents, bookmarks, highlights
        var id: String { rawValue }
        var title: String {
            switch self {
            case .contents: "Contents"
            case .bookmarks: "Bookmarks"
            case .highlights: "Highlights"
            }
        }
    }

    @State private var tab: Tab = .contents

    private var chapters: [Chapter] {
        viewModel.session?.document.chapters ?? []
    }

    private var currentChapterIndex: Int? {
        guard let session = viewModel.session else { return nil }
        return session.pageMap.pageRef(globalIndex: viewModel.currentGlobalIndex)?.chapterIndex
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                tabPicker
                Divider()
                content
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: Spacing.lg) {
            BookCoverView(book: book)
                .frame(width: 60, height: 90)
                .shadow(radius: 4)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(book.title)
                    .tText(.button)
                    .lineLimit(2)
                Text("Page \(viewModel.currentGlobalIndex + 1) of \(viewModel.totalPages)")
                    .tText(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button("Done") { dismiss() }
                .tText(.button, color: Theme.accent)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .contents: contentsList
        case .bookmarks: bookmarksList
        case .highlights: highlightsList
        }
    }

    // MARK: - 目录

    private var contentsList: some View {
        List {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                Button {
                    viewModel.jump(toChapter: index)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                            .tText(.body)
                            .lineLimit(1)
                        Spacer()
                        Text("\(chapterPageNumber(at: index))")
                            .tText(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(isCurrentChapter(index) ? Theme.inkFaint : Color.clear)
                        .padding(.horizontal, -Spacing.md)
                )
            }
        }
        .listStyle(.plain)
    }

    private func isCurrentChapter(_ index: Int) -> Bool {
        currentChapterIndex == index
    }

    /// 章节起始页码（1-based）。没有 EPUB page-list 时使用当前分页结果生成的页码。
    private func chapterPageNumber(at index: Int) -> Int {
        guard let session = viewModel.session else { return index + 1 }
        return (session.pageMap.chapterStartPage[safe: index] ?? 0) + 1
    }

    // MARK: - 书签

    @ViewBuilder
    private var bookmarksList: some View {
        if viewModel.bookmarks.isEmpty {
            emptyState(
                icon: "bookmark",
                title: "No Bookmarks",
                message: "Tap the bookmark button while reading to save your place."
            )
        } else {
            List {
                ForEach(viewModel.bookmarks) { bookmark in
                    Button {
                        viewModel.jump(to: bookmark.location)
                        dismiss()
                    } label: {
                        annotationRow(
                            leading: chapterTitle(bookmark.chapterIndex),
                            page: pageNumber(for: bookmark.location),
                            body: bookmark.snippet
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.removeBookmark(bookmark)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - 高亮

    @ViewBuilder
    private var highlightsList: some View {
        if viewModel.highlights.isEmpty {
            emptyState(
                icon: "highlighter",
                title: "No Highlights",
                message: "Select text while reading, then pick a color to highlight it."
            )
        } else {
            List {
                ForEach(viewModel.highlights) { highlight in
                    Button {
                        viewModel.jump(to: highlight.location)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            // 色块：一眼看出这条是什么颜色
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Color(highlight.color.uiColor))
                                .frame(width: Spacing.xs, height: Spacing.xl)
                            annotationRow(
                                leading: chapterTitle(highlight.chapterIndex),
                                page: pageNumber(for: highlight.location),
                                body: highlight.text
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.removeHighlight(highlight)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - 公共行

    private func annotationRow(leading: String, page: Int, body text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(leading)
                    .tText(.secondary)
                    .lineLimit(1)
                Text("p.\(page)")
                    .tText(.meta)
                    .monospacedDigit()
            }
            Text(text)
                .tText(.body)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .tIcon(IconRole.emphasis)
                .foregroundStyle(Theme.inkTertiary)
            Text(title)
                .tText(.sectionTitle)
            Text(message)
                .tText(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 查询

    private func chapterTitle(_ index: Int) -> String {
        chapters[safe: index]?.title ?? book.title
    }

    /// 位置 → 页码（1-based）。
    private func pageNumber(for location: ReaderLocation) -> Int {
        guard let index = viewModel.session?.globalIndex(for: location) else { return 1 }
        return index + 1
    }
}

// MARK: - Array helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
