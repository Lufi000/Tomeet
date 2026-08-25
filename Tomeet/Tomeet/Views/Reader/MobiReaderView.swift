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
                BookCoverView(book: book)
                    .frame(width: 140)

                Text(book.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("MOBI reader is coming soon.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            book.lastOpenedDate = .now
            try? modelContext.save()
        }
    }
}
