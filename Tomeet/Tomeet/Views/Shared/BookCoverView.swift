import SwiftUI

/// 封面：2:3 比例、小圆角；无封面图时占位图标（mvp.md §3.2 / §8.2）。
struct BookCoverView: View {
    let book: Book

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let name = book.coverImageName {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Image(systemName: "book.closed")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
    }
}