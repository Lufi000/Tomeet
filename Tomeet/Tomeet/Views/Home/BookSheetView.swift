import SwiftUI

/// 书籍详情 Sheet:底部滑入的磨砂面板(80% 屏高),含简介与读书/听书/对话入口。
/// 呈现/关闭动画由父视图控制 selectedBook 的 withAnimation(.spring)。
struct BookSheetView: View {
    let book: Book
    let onClose: () -> Void
    let onRead: () -> Void
    let onListen: () -> Void
    let onChat: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                panel
                    .frame(height: proxy.size.height * 0.8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
        .transition(.move(edge: .bottom))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
                BookCoverView(book: book)
                    .frame(height: 140)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.splendid(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.ink)
                    Text(book.author)
                        .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            }

            ScrollView {
                Text(book.summary ?? "暂无简介")
                    .font(.splendid(.body)).tracking(Theme.letterSpacing)
                    .foregroundStyle(book.summary == nil ? Theme.inkTertiary : Theme.ink)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                actionButton(title: "读书", systemImage: "book", primary: true,
                             enabled: true, action: onRead)
                actionButton(title: "听书", systemImage: "headphones", primary: false,
                             enabled: book.hasAudio, action: onListen)
                actionButton(title: "对话", systemImage: "bubble.left.and.bubble.right", primary: false,
                             enabled: true, action: onChat)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private func actionButton(title: String, systemImage: String, primary: Bool,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.splendid(.subheadline, weight: .semibold)).tracking(Theme.letterSpacing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(primary ? Theme.cream : Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(primary ? Theme.accent : Theme.card)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
