import SwiftUI

struct BookGridCell: View {
    let book: Book
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var newBadge: some View {
        Text("NEW")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue)) // §8.1 系统蓝底白字
            .padding(6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                BookCoverView(book: book)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                if book.showsNewBadge {
                    newBadge
                }
            }

            HStack(spacing: 4) {
                if let progress = book.progressText {
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if book.needsDownloadIcon {
                    Image(systemName: "icloud") // 未下载云朵（§3.2）
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(book.title)
                .font(.subheadline)
                .lineLimit(2)
            Text(book.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
