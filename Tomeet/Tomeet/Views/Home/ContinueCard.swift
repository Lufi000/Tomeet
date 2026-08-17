import SwiftUI

struct ContinueCard: View {
    let book: Book
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                BookCoverView(book: book)
                    .frame(width: 92)

                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(book.author) · \(book.format.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let progress = book.progressText {
                        Text(book.needsDownloadIcon ? "Not Downloaded" : "\(progress) complete")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Spacer(minLength: 4)

                Menu {
                    Button("More", systemImage: "ellipsis") {}
                        .disabled(true)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12)) // 深灰半透明卡片（§8.1）
            )
        }
        .buttonStyle(.plain)
    }
}