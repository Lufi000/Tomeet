import SwiftUI

/// 全书搜索占位 Sheet。真正全文搜索将在 AI 对话里程碑中实现。
struct SearchBookSheet: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Search in “\(book.title)”")
                    .font(.headline)

                Text("Full-text search across the book is coming soon.\nYou’ll be able to ask the book directly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .padding(.top, 60)
            .navigationTitle("Search Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
