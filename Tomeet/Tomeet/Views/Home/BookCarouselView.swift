import SwiftUI

/// Home 的横向书封轮播:左右滑动切换图书,松手吸附居中,居中书最大最清晰。
/// 顶部标题与底部 Add New Book 由 HomeView 固定层负责,这里只画轮播。
struct BookCarouselView: View {
    let books: [Book]
    /// 点已居中的书:打开详情面板。点侧边的书只会滚到居中。
    let onOpen: (Book) -> Void

    @State private var centeredID: UUID?

    var body: some View {
        GeometryReader { stage in
            let itemWidth = stage.size.width * 0.42
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(books) { book in
                        item(book, width: itemWidth, stageWidth: stage.size.width)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredID)
            // 首尾书也能滚到屏幕中心
            .contentMargins(.horizontal, (stage.size.width - itemWidth) / 2,
                            for: .scrollContent)
            .onAppear { centeredID = books.first?.id }
            .onChange(of: books.map(\.id)) { _, ids in
                // 居中的书被删(或尚未居中)时退到第一本
                if let id = centeredID, !ids.contains(id) {
                    centeredID = ids.first
                } else if centeredID == nil {
                    centeredID = ids.first
                }
            }
        }
    }

    private func item(_ book: Book, width: CGFloat, stageWidth: CGFloat) -> some View {
        Button {
            if centeredID == book.id {
                onOpen(book)
            } else {
                withAnimation(.spring) { centeredID = book.id }
            }
        } label: {
            VStack(spacing: 8) {
                BookCoverView(book: book)
                    .frame(width: width)
                Text(book.title)
                    .font(.splendid(.headline, weight: .semibold)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(book.author)
                    .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        // visualEffect 只改呈现不改布局,滚动中逐帧拿到位置
        .visualEffect { content, proxy in
            let midX = proxy.frame(in: .global).midX
            return content
                .scaleEffect(CarouselScale.scale(midX: midX, screenWidth: stageWidth))
                .opacity(CarouselScale.opacity(midX: midX, screenWidth: stageWidth))
        }
    }
}
