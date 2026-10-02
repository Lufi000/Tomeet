import Foundation
import Testing
import UIKit
@testable import Tomeet

/// 把阅读页**离屏渲染成 PNG**，用于人工核对视觉效果。
///
/// 为什么需要它：模拟器没法自动点击，跑不到"打开书 → 翻页"这一步，
/// 而纯逻辑测试证明不了"角标看起来是上标""高亮真的有底色""插图真的画出来了"。
/// 直接把 `ReaderPageVC` 画出来存成图片，就能用眼睛验收。
///
/// 输出目录：`/tmp/tomeet-render/`（跑完可以去那里看图）
struct PageSnapshotTests {

    private var outputDirectory: URL {
        URL(fileURLWithPath: "/tmp/tomeet-render", isDirectory: true)
    }

    private let pageSize = CGSize(width: 393, height: 852)

    // MARK: - Fixture

    /// 造一张纯色 PNG 存到临时目录，当作书里的插图。
    private func makeImage(at url: URL, color: UIColor, size: CGSize) throws {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: size.width * 0.2, y: size.height * 0.2,
                                width: size.width * 0.6, height: size.height * 0.6))
        }
        try image.pngData()?.write(to: url)
    }

    private func makeBook(root: URL) throws -> BookDocument {
        try makeImage(
            at: root.appendingPathComponent("pic.png"),
            color: UIColor(red: 0.42, green: 0.51, blue: 0.27, alpha: 1),
            size: CGSize(width: 900, height: 600)
        )

        let body = String(repeating: "理解复杂系统，关键在于看清大量简单个体如何涌现出整体行为。", count: 6)
        let chapter = Chapter(id: "c0", title: "第一章 复杂性是什么", blocks: [
            .heading(level: 1, text: "第一章 复杂性是什么"),
            .paragraph(runs: [
                InlineRun("我研究了布氏游蚁"),
                InlineRun("12", noteID: "note12"),
                InlineRun("很多年，我发现，对它们的社会结构了解得越多，对其社会组织的疑问就会越多。"),
            ]),
            .paragraph(body),
            .image(ImageRef(path: "pic.png", alt: "示意图")),
            .paragraph("上面这张图展示了蚁群的自组织行为。"),
            .quote("整体大于部分之和。"),
        ])
        return BookDocument(
            title: "复杂",
            author: "[美] 梅拉妮·米歇尔",
            language: "zh",
            chapters: [chapter],
            baseURL: root,
            anchors: ["note12": ReaderLocation(chapterIndex: 0, charOffset: 999)]
        )
    }

    // MARK: - 渲染

    @MainActor
    private func snapshot(
        book: BookDocument,
        theme: ReaderTheme,
        highlights: [Highlight],
        name: String
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var context = PaginationContext(pageSize: pageSize)
        context.theme = theme
        context.safeAreaInsets = ContentInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        context.apply(SpacingPreset.normal)

        let pages = ChapterPager.paginate(book: book, context: context)
        let chapterPages = try #require(pages.first?.pages, "分页应至少产出一页")

        // 每一页都渲染出来 —— 插图/引文可能落在后面的页上，只画首页会漏掉。
        for (index, textPage) in chapterPages.enumerated() {
            let pageVC = ReaderHostView.ReaderPageVC(
                theme: theme,
                insets: context.resolvedInsets.uiEdgeInsets
            )
            pageVC.configure(text: textPage, highlights: highlights)
            pageVC.view.frame = CGRect(origin: .zero, size: pageSize)
            pageVC.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: pageSize)
            let image = renderer.image { _ in
                pageVC.view.drawHierarchy(in: pageVC.view.bounds, afterScreenUpdates: true)
            }
            let destination = outputDirectory.appendingPathComponent(
                "\(name)-p\(index + 1).png"
            )
            try image.pngData()?.write(to: destination)
            print("### 已渲染 \(destination.path)")
        }
        print("### \(name) 共 \(chapterPages.count) 页")
    }

    @Test @MainActor func rendersTitleAndFootnoteMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try snapshot(
            book: try makeBook(root: root),
            theme: .paper,
            highlights: [],
            name: "01-paper-marker"
        )
    }

    @Test @MainActor func rendersHighlightedText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let book = try makeBook(root: root)
        let highlight = Highlight(
            bookID: UUID(),
            chapterIndex: 0,
            charOffset: 0,
            length: 12,
            color: .blue,
            text: "我研究了布氏游蚁"
        )
        try snapshot(book: book, theme: .paper, highlights: [highlight], name: "02-highlight")
    }

    @Test @MainActor func rendersDarkTheme() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try snapshot(
            book: try makeBook(root: root),
            theme: .ink,
            highlights: [],
            name: "03-ink"
        )
    }
}

private extension PaginationContext {
    mutating func apply(_ preset: SpacingPreset) {
        lineSpacing = CGFloat(preset.lineSpacing)
        paragraphSpacing = CGFloat(preset.paragraphSpacing)
        lineHeightMultiple = CGFloat(preset.lineHeightMultiple)
    }
}
