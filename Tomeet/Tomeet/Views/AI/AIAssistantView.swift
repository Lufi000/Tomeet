import SwiftUI

struct AIAssistantView: View {
    /// 对话绑定的书(从 Book Sheet 的「对话」按钮进入,上下文固定)。
    let book: Book
    /// 关闭全屏对话页(由父视图把 presentedChat 置 nil)。
    var onBack: () -> Void

    init(book: Book, onBack: @escaping () -> Void) {
        self.book = book
        self.onBack = onBack
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                BookChatView(book: book)
            }
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .simultaneousGesture(edgeSwipeBack)
        }
    }

    /// 全屏页没有系统的右滑 pop 手势，手动补一个左边缘右滑返回
    private var edgeSwipeBack: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard value.startLocation.x < 40,
                      value.translation.width > 60,
                      abs(value.translation.height) < 80 else { return }
                onBack()
            }
    }

    // MARK: - Context card

    /// 静态上下文卡片:封面 + "Asking about" + 书名(上下文固定,不可切换)。
    private var contextCard: some View {
        HStack(spacing: 12) {
            BookCoverView(book: book).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asking about")
                    .font(.splendid(.caption2)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkTertiary)
                Text(book.title)
                    .font(.splendid(.subheadline, weight: .medium)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
        )
    }
}
