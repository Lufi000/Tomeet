import SwiftUI
import SwiftData

/// MOBI 阅读器占位视图：导入后即可出现在书架，但完整渲染后续接入。
struct MobiReaderView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                }

                BookCoverView(book: book)
                    .frame(width: 140)

                Text(book.title)
                    .font(.splendid(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                    .multilineTextAlignment(.center)

                Text(book.author)
                    .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                    .foregroundStyle(.secondary)

                Text("MOBI reader is coming soon.")
                    .font(.splendid(.body)).tracking(Theme.letterSpacing)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .padding()
            // 系统内联标题字体无法定制，Done 挪进页面顶部
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            book.lastOpenedDate = .now
            try? modelContext.save()
        }
    }
}
