import SwiftUI

struct ContinueCard: View {
    let book: Book
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                BookCoverView(book: book)
                    .frame(width: 92)

                // 文字区主动占满剩余宽度（右上角按钮只占角上一小块，不挤标题）
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .splendidContentFont(.title3, text: book.title)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text("\(book.author) · \(book.format.label)")
                        .splendidContentFont(.subheadline, text: "\(book.author) · \(book.format.label)")
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.card)
            )
        }
        .buttonStyle(.plain)
        // 点点点菜单固定在卡片右上角，不占用文字排布空间
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("More", systemImage: "ellipsis") {}
                    .disabled(true)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(10)
            }
        }
        // 阅读进度固定在卡片右下角，嫩绿加粗
        .overlay(alignment: .bottomTrailing) {
            if let progress = book.progressText {
                Text(book.needsDownloadIcon ? "Not Downloaded" : "\(progress) complete")
                    .font(.splendid(.subheadline, weight: .semibold)).splendidTracking(.subheadline)
                    .foregroundStyle(Theme.progress)
                    .padding(12)
            }
        }
    }
}
