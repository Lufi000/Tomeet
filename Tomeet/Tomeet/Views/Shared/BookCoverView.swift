import SwiftUI

/// 封面：2:3 比例、小圆角；无封面图时占位图标（mvp.md §3.2 / §8.2）。
///
/// 加载优先级：
/// 1. `book.coverImageName` 指定的 asset-catalog 图片（保留用户导入/自定义书籍）。
/// 2. EPUB 内嵌封面图片（从解压后的 EPUB 目录读取）。
/// 3. 系统 `book.closed` 占位图标。
struct BookCoverView: View {
    let book: Book

    @State private var coverImage: UIImage?
    /// 封面已加载的书：SwiftUI 复用 view 时 @State 不重置，靠它识别换书并重载
    @State private var loadedBookID: UUID?

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let name = book.coverImageName {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                } else if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Theme.shell
                        Image(systemName: "book.closed")
                            .font(.title)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
            .task(id: book.id) {
                await loadEmbeddedCover()
            }
    }

    private func loadEmbeddedCover() async {
        guard loadedBookID != book.id else { return }
        loadedBookID = book.id
        coverImage = nil
        guard book.coverImageName == nil,
              let directoryURL = BookSourceResolver.existingDirectoryURL(for: book) else {
            return
        }

        do {
            if let coverURL = try EPUBCoverExtractor.coverURL(in: directoryURL),
               let image = UIImage(contentsOfFile: coverURL.path) {
                coverImage = image
            }
        } catch {
            // 封面读取失败时静默使用占位图标。
        }
    }
}
