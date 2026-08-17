import SwiftUI
import SwiftData

/// mvp.md §4：底部上滑大圆角 Sheet，.medium/.large 两档。
struct CollectionsSheet: View {
    let books: [Book]
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let count: Int
    }

    private var rows: [Row] {
        [
            Row(title: "Want to Read", icon: "bookmark",
                count: books.filter { $0.isNew }.count),
            Row(title: "Finished", icon: "checkmark.circle",
                count: books.filter { $0.readingProgress == 1 }.count),
            Row(title: "Books", icon: "books.vertical",
                count: books.filter { $0.format == .epub }.count),
            Row(title: "Audiobooks", icon: "headphones",
                count: books.filter { $0.format == .audiobook }.count),
            Row(title: "PDFs", icon: "doc.richtext",
                count: books.filter { $0.format == .pdf }.count),
            Row(title: "My Samples", icon: "doc.fill", count: 0),
            Row(title: "Downloaded", icon: "arrow.down.circle",
                count: books.filter { $0.isDownloaded }.count),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    HStack {
                        Image(systemName: row.icon)
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text(row.title)
                        Spacer()
                        Text("\(row.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
                    Button("New Collection...") {
                        // M1 占位：自定义合集持久化放 Milestone 2（§4）
                    }
                    .disabled(true)
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {}
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}