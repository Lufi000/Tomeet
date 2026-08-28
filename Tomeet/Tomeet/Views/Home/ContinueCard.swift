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
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.splendid(.headline)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text("\(book.author) · \(book.format.label)")
                        .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    if let progress = book.progressText {
                        Text(book.needsDownloadIcon ? "Not Downloaded" : "\(progress) complete")
                            .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                            .foregroundStyle(Theme.accent)
                    }
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
    }
}
