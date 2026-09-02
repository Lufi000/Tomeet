import SwiftUI

struct BookGridCell: View {
    let book: Book
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var newBadge: some View {
        Text("NEW")
            .font(.splendid(.caption2, weight: .bold)).splendidTracking(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.accent))
            .padding(6)
    }

    // 听书角标：该书附带音频时显示在封面右上角
    private var audioBadge: some View {
        Image(systemName: "headphones")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(Color.black.opacity(0.65)))
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
            .overlay(alignment: .topTrailing) {
                if book.hasAudio {
                    audioBadge
                }
            }

            HStack(spacing: 4) {
                if let progress = book.progressText {
                    Text(progress)
                        .font(.splendid(.caption)).splendidTracking(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if book.needsDownloadIcon {
                    Image(systemName: "icloud") // 未下载云朵（§3.2）
                        .font(.caption2)
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
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Text(book.title)
                .splendidContentFont(.subheadline, text: book.title)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(book.author)
                .splendidContentFont(.caption2, text: book.author)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
    }
}
