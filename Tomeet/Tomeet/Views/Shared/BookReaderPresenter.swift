import SwiftUI

/// 按书籍格式分发到对应阅读器(Home 的 Book Sheet 与 Library 共用)。
enum BookReaderPresenter {
    @ViewBuilder
    static func view(for book: Book) -> some View {
        switch book.format {
        case .pdf:
            PDFReaderView(book: book)
        case .mobi:
            MobiReaderView(book: book)
        case .epub, .audiobook:
            ReaderView(book: book)
        }
    }
}
