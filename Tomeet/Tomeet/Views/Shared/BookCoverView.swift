import SwiftUI

/// 封面：2:3 比例；无封面图时占位图标。
///
/// 加载优先级：
/// 1. `book.coverImageName` 指定的 asset-catalog 图片（保留用户导入/自定义书籍）。
/// 2. EPUB 内嵌封面图片（从解压后的 EPUB 目录读取）。
/// 3. 系统 `book.closed` 占位图标。
struct BookCoverView: View {
    /// 封面出现在哪里 —— 决定圆角形状。
    enum Style {
        /// 列表缩略图：四角同圆。
        case thumbnail
        /// 书架：**只圆右侧两角**，左侧是直角。
        ///
        /// 这是设计稿「书脊朝左立在架上」的处理 —— 左边是书脊，不该圆。
        /// 投影由调用点用 `.shelfShadow()` 加（缩略图不需要）。
        case shelf
    }

    let book: Book
    var style: Style = .thumbnail

    @State private var coverImage: UIImage?

    /// 形状只定义一次，裁剪与描边共用 —— 两处各写一遍必然会漂移。
    private var shape: UnevenRoundedRectangle {
        switch style {
        case .thumbnail:
            return UnevenRoundedRectangle(
                topLeadingRadius: Radius.sm, bottomLeadingRadius: Radius.sm,
                bottomTrailingRadius: Radius.sm, topTrailingRadius: Radius.sm,
                style: .continuous
            )
        case .shelf:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: Radius.sm, topTrailingRadius: Radius.sm,
                style: .continuous
            )
        }
    }

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
                            // 图标永远走 SF Pro —— SF Symbols 没有圆体变体，
                            // 挂上文字字体只会落到回退字形。
                            .tIcon(.title)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Theme.onSolid.opacity(0.15), lineWidth: 0.5)
            }
            .task {
                await loadEmbeddedCover()
            }
    }

    private func loadEmbeddedCover() async {
        guard coverImage == nil, book.coverImageName == nil,
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
