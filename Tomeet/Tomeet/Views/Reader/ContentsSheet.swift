import SwiftUI

/// 目录 Sheet：封面 + 书名 + 当前页码 + 章节列表（高亮当前章）。
struct ContentsSheet: View {
    let book: Book
    let viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    private var chapters: [Chapter] {
        viewModel.session?.document.chapters ?? []
    }

    private var currentChapterIndex: Int? {
        guard let session = viewModel.session else { return nil }
        return session.pageMap.pageRef(globalIndex: viewModel.currentGlobalIndex)?.chapterIndex
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                chapterSection
            }
            .listStyle(.plain)
            // 系统内联标题字体无法定制，Done 挪进封面行（见 headerSection）
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            BookCoverView(book: book)
                .frame(width: 60, height: 90)
                .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .splendidContentFont(.headline, text: book.title)
                    .lineLimit(2)
                Text("Page \(viewModel.currentGlobalIndex + 1) of \(viewModel.totalPages)")
                    .font(.splendid(.subheadline)).splendidTracking(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    // MARK: - 章节列表

    private var chapterSection: some View {
        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
            Button {
                viewModel.jump(toChapter: index)
                dismiss()
            } label: {
                HStack {
                    Text(chapter.title)
                        .splendidContentFont(.body, text: chapter.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(chapterPageNumber(at: index))")
                        .font(.splendid(.subheadline)).splendidTracking(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCurrentChapter(index) ? Color.gray.opacity(0.2) : Color.clear)
                    .padding(.horizontal, -12)
            )
        }
    }

    private func isCurrentChapter(_ index: Int) -> Bool {
        currentChapterIndex == index
    }

    /// 章节起始页码（1-based）。没有 EPUB page-list 时使用当前分页结果生成的页码。
    private func chapterPageNumber(at index: Int) -> Int {
        guard let session = viewModel.session else { return index + 1 }
        return (session.pageMap.chapterStartPage[safe: index] ?? 0) + 1
    }
}

// MARK: - Array helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
