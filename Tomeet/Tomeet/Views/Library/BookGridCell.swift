import SwiftUI

/// 书架单元：**书名/作者在上，封面在下**（设计稿结构），封面 2:3、只圆右侧两角。
struct BookGridCell: View {
    let book: Book
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 文字块在上：书名 + 作者紧贴（xs），整块离封面 md。
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(book.title)
                    .tText(.cellTitle)
                    .lineLimit(2)
                Text(book.author)
                    .tText(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.md)

            Button(action: onOpen) {
                BookCoverView(book: book, style: .shelf)
                    .shelfShadow()
                    // 把封面在本帧中的全局坐标上报给书架，弹层据此做「从原位翻起」。
                    // 必须挂在**封面**上而不是整格 —— 单元格还包括文字与角标，
                    // 拿整格的 frame 会让弹层从一个比封面大的矩形起飞。
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BookCoverFramePreferenceKey.self,
                                value: [book.id: proxy.frame(in: .global)]
                            )
                        }
                    }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                if book.showsNewBadge { TBadge.text("NEW") }
            }
            .overlay(alignment: .topTrailing) {
                if book.hasAudio { TBadge.icon("headphones") }
            }

            // 进度与删除菜单是设计稿没画、但 App 已有的功能，保留在封面下方，
            // 用最轻的 meta 角色，不抢书名与封面的注意力。
            HStack(spacing: Spacing.xs) {
                if let progress = book.progressText {
                    Text(progress).tText(.meta)
                }
                Spacer()
                if book.needsDownloadIcon {
                    Image(systemName: "icloud")
                        .tIcon(IconRole.badge)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .tIcon(IconRole.badge)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }
}
