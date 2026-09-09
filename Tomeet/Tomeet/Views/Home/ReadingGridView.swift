import SwiftUI

/// Home 的「最近在读」封面网格:两列纵向滚动,item 随滚动呼吸缩放。
/// 顶部标题与底部 Add New Book 由 HomeView 的 ZStack 固定层负责,这里只画网格。
struct ReadingGridView: View {
    let books: [Book]
    let onSelect: (Book) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        GeometryReader { stage in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(books) { book in
                        Button { onSelect(book) } label: {
                            cellContent(book)
                        }
                        .buttonStyle(.plain)
                        // visualEffect 只改呈现不改布局,滚动中逐帧拿到 global 位置
                        .visualEffect { content, proxy in
                            let midY = proxy.frame(in: .global).midY
                            return content
                                .scaleEffect(BreathingScale.scale(midY: midY, screenHeight: stage.size.height))
                                .opacity(BreathingScale.opacity(midY: midY, screenHeight: stage.size.height))
                        }
                    }
                }
                .padding(.horizontal, 20)
                // 顶部给固定标题让位,底部给 Add New Book 胶囊让位
                .padding(.top, 170)
                .padding(.bottom, 130)
            }
        }
    }

    private func cellContent(_ book: Book) -> some View {
        VStack(spacing: 8) {
            BookCoverView(book: book)
            Text(book.title)
                .font(.splendid(.caption, weight: .semibold)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(book.author)
                .font(.splendid(.caption2)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
    }
}
