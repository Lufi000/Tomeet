import SwiftUI
import PDFKit
import SwiftData

/// 使用 PDFKit 渲染 PDF，启用原生 page curl 翻页。
struct PDFReaderView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var pdfURL: URL? {
        BookSourceResolver.fileURL(for: book, extension: "pdf")
    }

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    PDFKitRepresentedView(url: pdfURL)
                } else {
                    ContentUnavailableView(
                        "PDF Not Found",
                        systemImage: "doc.questionmark",
                        description: Text("The PDF file is missing from storage.")
                    )
                }
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            book.lastOpenedDate = .now
            try? modelContext.save()
        }
    }
}

private struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
