import SwiftUI

/// 书籍详情面板:近全屏磨砂面板(底部滑入),对话优先。
/// 点封面进阅读器;右上菜单含「听书」。呈现/关闭动画由父视图 withAnimation(.spring) 控制。
struct BookDetailView: View {
    let book: Book
    let onClose: () -> Void
    let onRead: () -> Void
    let onListen: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                panel
                    // 顶部留安全区 + 12pt,近全屏;键盘弹出时 proxy 高度收缩,面板随之被顶起
                    .frame(height: proxy.size.height - 12)
                    .frame(maxWidth: .infinity)
                    // 磨砂背景单独延伸到屏幕底边;内容不 ignore,由 padding 抬离 Home 指示条
                    .background {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.regularMaterial)
                            .ignoresSafeArea(.container, edges: .bottom)
                    }
                    .simultaneousGesture(swipeDownToClose)
            }
        }
        .transition(.move(edge: .bottom))
    }

    /// 下滑关闭:垂直下拖超过 80pt 且横向位移小于纵向时关闭,不拦截按钮点击。
    private var swipeDownToClose: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let t = value.translation
                guard t.height > 80, abs(t.width) < t.height else { return }
                onClose()
            }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶栏:左关闭,右菜单(听书)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Button {
                        onListen()
                    } label: {
                        Label("听书", systemImage: "headphones")
                    }
                    .disabled(!book.hasAudio)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            // 书籍区:封面在上、书名作者在下方,全左对齐;封面可点 → 进阅读器
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onRead) {
                    BookCoverView(book: book)
                        .frame(height: 120)
                }
                .buttonStyle(.plain)
                Text(book.title)
                    .font(.book(.title3, weight: .bold)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                Text(book.author)
                    .font(.book(.subheadline)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            BookChatView(book: book)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}
