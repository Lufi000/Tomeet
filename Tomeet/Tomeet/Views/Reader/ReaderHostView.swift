import SwiftUI
import UIKit

/// UIPageViewController .pageCurl 翻页桥。
struct ReaderHostView: UIViewControllerRepresentable {
    let viewModel: ReaderViewModel
    var onToggleChrome: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, onToggleChrome: onToggleChrome)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.isDoubleSided = false
        context.coordinator.pageViewController = pageViewController

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        pageViewController.view.addGestureRecognizer(tap)

        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.applyThemeIfNeeded()
        context.coordinator.reconcile(pageViewController)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var viewModel: ReaderViewModel
        var onToggleChrome: (() -> Void)?
        weak var pageViewController: UIPageViewController?
        private var pages: [Int: UIViewController] = [:]
        private var shownGlobalIndex: Int?
        private var appliedTheme: ReaderTheme?
        /// 上次排版会话的标识；换边距/字号/旋转会重建 session，此时必须清掉旧页缓存。
        private var cachedSessionID: ObjectIdentifier?
        /// 上次渲染时的高亮指纹，用于判断缓存页是否需要重画。
        private var appliedHighlightSignature = ""

        init(viewModel: ReaderViewModel, onToggleChrome: (() -> Void)? = nil) {
            self.viewModel = viewModel
            self.onToggleChrome = onToggleChrome
        }

        func applyThemeIfNeeded() {
            let theme = viewModel.settings?.theme ?? .original
            guard appliedTheme != theme else { return }
            appliedTheme = theme
            for case let pageVC as ReaderPageVC in pages.values {
                pageVC.apply(theme: theme)
            }
        }

        func reconcile(_ pageViewController: UIPageViewController) {
            if let session = viewModel.session {
                let id = ObjectIdentifier(session)
                if id != cachedSessionID {
                    cachedSessionID = id
                    pages.removeAll()
                    shownGlobalIndex = nil
                    appliedTheme = nil
                }
            }
            // 高亮增删改色后，缓存页里的是旧底色 —— 整体作废重画。
            let signature = highlightSignature()
            if signature != appliedHighlightSignature {
                appliedHighlightSignature = signature
                pages.removeAll()
                shownGlobalIndex = nil
            }
            guard viewModel.phase == .ready else { return }
            let target = viewModel.currentGlobalIndex
            guard target >= 0, target < viewModel.totalPages else { return }
            if shownGlobalIndex != target {
                // 只在相邻翻页时播动画；跳转（脚注/目录/书签）直接就位，避免长距离卷页。
                let animated = shownGlobalIndex.map { abs(target - $0) == 1 } ?? false
                setPage(target, animated: animated)
                shownGlobalIndex = target
            }
            trimCache(around: target)
        }

        private func setPage(_ index: Int, animated: Bool) {
            guard let pageViewController,
                  let viewController = page(for: index)
            else { return }
            pageViewController.setViewControllers(
                [viewController],
                direction: .forward,
                animated: animated,
                completion: nil
            )
        }

        private func page(for index: Int) -> UIViewController? {
            guard index >= 0, index < viewModel.totalPages else { return nil }
            if let cached = pages[index] { return cached }
            guard let text = viewModel.session?.pageMap.textPage(globalIndex: index) else { return nil }
            let theme = viewModel.settings?.theme ?? .original
            // 内衬必须取自分页上下文：分页算换行宽度、这里算文字位置，两边不一致就会错位。
            let insets = viewModel.paginationContext?.resolvedInsets.uiEdgeInsets ?? Self.defaultInsets
            let pageVC = ReaderPageVC(theme: theme, insets: insets)
            let chapterIndex = viewModel.session?.pageMap.pageRef(globalIndex: index)?.chapterIndex ?? 0
            pageVC.configure(text: text, highlights: viewModel.highlights(chapterIndex: chapterIndex))
            pageVC.onHighlight = { [weak self] chapterRange, selectedText, color in
                self?.viewModel.addHighlight(range: chapterRange, color: color, text: selectedText)
            }
            pages[index] = pageVC
            return pageVC
        }

        /// 高亮集合的指纹。变了才需要让缓存页重画底色。
        private func highlightSignature() -> String {
            viewModel.highlights.map { "\($0.id.uuidString):\($0.colorRaw)" }.joined(separator: ",")
        }

        /// 上下文尚未建立时的兜底内衬，与 ReaderSettings 默认值一致。
        private static let defaultInsets = UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28)

        private func trimCache(around index: Int) {
            for key in pages.keys where abs(key - index) > 4 {
                pages.removeValue(forKey: key)
            }
        }

        // MARK: - 点击

        /// 点脚注角标 → 跳到注释；点其他任何地方 → 切换悬浮菜单。
        /// 翻页**只**由滑动手势触发（此前左 30%/右 30% 点击会翻页，阅读时极易误触）。
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            if let pageVC = pageViewController?.viewControllers?.first as? ReaderPageVC,
               let point = gesture.view.map({ pageVC.view.convert(gesture.location(in: $0), from: $0) }),
               let noteID = pageVC.noterefID(at: point),
               viewModel.jump(toAnchor: noteID) {
                return
            }
            onToggleChrome?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // 点击等待滑动手势失败后再响应，确保翻页滑动优先。
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let index = index(of: viewController) else { return nil }
            return page(for: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let index = index(of: viewController) else { return nil }
            return page(for: index + 1)
        }

        private func index(of viewController: UIViewController) -> Int? {
            pages.first(where: { $0.value === viewController })?.key
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pageViewController.viewControllers?.first,
                  let index = index(of: current)
            else { return }
            shownGlobalIndex = index
            viewModel.settle(globalIndex: index)
        }
    }

    // MARK: - Page VC

    /// 单页：禁滚动的 UITextView，只承载排版好的 attributed text。
    /// 内衬必须与分页时的 `PaginationContext.resolvedInsets` 完全一致 ——
    /// 分页按它算换行宽度，这里按它摆文字，差一点就会换行错位。
    @MainActor
    final class ReaderPageVC: UIViewController, UITextViewDelegate {
        private let textView = UITextView()
        /// 章首页的章标题与它左侧的竖线；只有章节第一页会显示。
        private let titleLabel = UILabel()
        private let titleRule = UIView()
        /// 引文块左侧的竖线；一页可能有多段引文，一次画完。
        private let quoteRules = QuoteRuleView()
        private let theme: ReaderTheme
        private let insets: UIEdgeInsets

        /// 用户选了字并挑了一个高亮颜色。参数：**章内** canonical 区间、选中原文、颜色。
        var onHighlight: (@MainActor (NSRange, String, HighlightColor) -> Void)?

        /// 本页在所属章节 canonical 空间中的区间；选中的区域要加上这个偏移才是章内区间。
        private var pageRange = NSRange(location: 0, length: 0)
        /// 本页的章标题（仅章节第一页有）。高度由分页端量好，这里只照着摆。
        private var header: PageHeader?

        init(theme: ReaderTheme, insets: UIEdgeInsets = UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28)) {
            self.theme = theme
            self.insets = insets
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            self.theme = .original
            self.insets = UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28)
            super.init(coder: coder)
        }

        override func loadView() {
            textView.isEditable = false
            // 可选中才能长按选字做高亮。滚动仍禁用：翻页交给 UIPageViewController。
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.delegate = self
            textView.backgroundColor = UIColor(theme.backgroundColor)
            // 文字颜色由 NSAttributedString 携带的主题色/强调色控制。
            textView.textContainerInset = insets
            textView.textContainer.lineFragmentPadding = 0

            // 标题与竖线挂成正文视图的子视图：位置靠 textContainerInset 让出来的那一块，
            // 不参与文字排版，也就不影响换行。
            titleLabel.numberOfLines = 0
            titleLabel.isUserInteractionEnabled = false
            titleLabel.isHidden = true
            titleRule.isUserInteractionEnabled = false
            titleRule.isHidden = true
            quoteRules.isUserInteractionEnabled = false
            // 这个视图只画几根竖线，其余像素必须透出底下正文视图的背景色。
            // 一旦它是 opaque，没画到的像素会被渲染成黑 —— 整页变黑底。
            quoteRules.isOpaque = false
            quoteRules.backgroundColor = .clear
            quoteRules.frame = textView.bounds
            quoteRules.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            textView.addSubview(quoteRules)
            textView.addSubview(titleRule)
            textView.addSubview(titleLabel)
            view = textView
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            quoteRules.color = UIColor(theme.textColor).withAlphaComponent(ChapterPager.quoteRuleOpacity)
            quoteRules.rects = quoteRuleRects()
            guard let header else { return }
            // 竖线从标题首行顶端画到末行底端，宽度与槽宽都取自分页端。
            titleRule.frame = CGRect(
                x: insets.left,
                y: insets.top,
                width: header.ruleWidth,
                height: header.titleHeight
            )
            titleLabel.frame = CGRect(
                x: insets.left + header.ruleGutter,
                y: insets.top,
                width: max(0, view.bounds.width - insets.left - insets.right - header.ruleGutter),
                height: header.titleHeight
            )
        }

        /// 引文竖线的位置：本页每一段引文的行片段并入一个矩形，画在缩进槽里。
        ///
        /// 用**和分页同一套引擎**（TextKit 1 + 同样的容器尺寸）重量一遍这一页，
        /// 而不是问 `textView.layoutManager` 要几何 —— 后者报出来的和真正画在屏上的
        /// 不是一回事（分页/上屏字体那个 bug 就是这么藏了很久的）。
        private func quoteRuleRects() -> [CGRect] {
            let text = textView.attributedText ?? NSAttributedString()
            let fullRange = NSRange(location: 0, length: text.length)
            guard fullRange.length > 0 else { return [] }
            var hasQuote = false
            text.enumerateAttribute(.tomeetQuote, in: fullRange) { value, _, stop in
                if value != nil {
                    hasQuote = true
                    stop.pointee = true
                }
            }
            guard hasQuote else { return [] }

            let pageInsets = textView.textContainerInset
            let storage = NSTextStorage(attributedString: text)
            let manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            let container = NSTextContainer(size: CGSize(
                width: max(1, view.bounds.width - pageInsets.left - pageInsets.right),
                height: max(1, view.bounds.height - pageInsets.top - pageInsets.bottom)
            ))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)

            var rects: [CGRect] = []
            text.enumerateAttribute(.tomeetQuote, in: fullRange) { value, range, _ in
                guard value != nil else { return }
                let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var glyph = glyphs.location
                let end = NSMaxRange(glyphs)
                var union = CGRect.null
                while glyph < end {
                    var lineRange = NSRange(location: 0, length: 0)
                    union = union.union(manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange))
                    guard lineRange.length > 0 else { break }
                    glyph = NSMaxRange(lineRange)
                }
                guard !union.isNull else { return }
                rects.append(CGRect(
                    x: pageInsets.left + ChapterPager.quoteRuleInset,
                    y: pageInsets.top + union.minY,
                    width: ChapterPager.quoteRuleWidth,
                    height: union.height
                ))
            }
            return rects
        }

        // MARK: 选字菜单

        /// 长按选字后弹出的菜单：四色高亮 + 系统建议项（复制/查询…）。
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let selected = (textView.text as NSString).substring(with: range)
            let chapterRange = NSRange(
                location: pageRange.location + range.location,
                length: range.length
            )
            let colorActions = HighlightColor.allCases.map { color in
                UIAction(title: color.displayName, image: Self.swatch(for: color)) { [weak self] _ in
                    self?.onHighlight?(chapterRange, selected, color)
                    self?.clearSelection()
                }
            }
            let highlightMenu = UIMenu(
                title: "Highlight",
                options: .displayInline,
                children: colorActions
            )
            return UIMenu(children: [highlightMenu] + suggestedActions)
        }

        private func clearSelection() {
            textView.selectedRange = NSRange(location: 0, length: 0)
        }

        /// 菜单里的小圆点，让颜色一眼可辨。
        private static func swatch(for color: HighlightColor) -> UIImage {
            let size = CGSize(width: 18, height: 18)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                context.cgContext.setFillColor(color.uiColor.withAlphaComponent(1).cgColor)
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
        }

        func apply(theme: ReaderTheme) {
            textView.backgroundColor = UIColor(theme.backgroundColor)
            titleRule.backgroundColor = UIColor(theme.accentColor)
        }

        func configure(text: TextPage, highlights: [Highlight] = []) {
            // 先把视图树逼出来：`loadView` 会重置标题与内衬的初值，
            // 若是被下面某一行间接触发，刚设好的状态就被它盖回去了。
            loadViewIfNeeded()
            pageRange = text.characterRange
            header = text.header
            // 章首页：正文整体下移标题占掉的那一块。高度是分页端量好的，这里不重算。
            var pageInsets = insets
            if let header {
                pageInsets.top += header.totalHeight
                titleLabel.attributedText = header.text
                titleRule.backgroundColor = UIColor(theme.accentColor)
            }
            textView.textContainerInset = pageInsets
            titleLabel.isHidden = header == nil
            titleRule.isHidden = header == nil
            view.setNeedsLayout()

            let attributed = resolveImages(in: text.text)
            textView.attributedText = applyHighlights(highlights, to: attributed, pageRange: text.characterRange)
        }

        /// 把落在本页的高亮涂上底色。
        ///
        /// 高亮存的是**章内** canonical 偏移，页里的是本页区间，所以要平移：
        /// `页内偏移 = 章内偏移 - 本页在章内的起点`。
        private func applyHighlights(
            _ highlights: [Highlight],
            to attributed: NSAttributedString,
            pageRange: NSRange
        ) -> NSAttributedString {
            guard !highlights.isEmpty, attributed.length > 0 else { return attributed }
            let mutable = NSMutableAttributedString(attributedString: attributed)
            for highlight in highlights {
                let overlap = NSIntersectionRange(highlight.range, pageRange)
                guard overlap.length > 0 else { continue }
                let local = NSRange(
                    location: overlap.location - pageRange.location,
                    length: overlap.length
                )
                guard local.location >= 0, local.location + local.length <= mutable.length else { continue }
                mutable.addAttribute(.backgroundColor, value: highlight.color.uiColor, range: local)
                mutable.addAttribute(.tomeetHighlight, value: highlight.id.uuidString, range: local)
            }
            return mutable
        }

        /// 把待加载的图片附件换成真正解码好的位图。
        ///
        /// 只在**这一页上屏时**做 —— 分页阶段整本书的页都在内存里，
        /// 那时解码会把整本书的图一起拉进来。降采样到屏幕实际需要的大小。
        private func resolveImages(in attributed: NSAttributedString) -> NSAttributedString {
            guard attributed.length > 0 else { return attributed }
            let mutable = NSMutableAttributedString(attributedString: attributed)
            let fullRange = NSRange(location: 0, length: mutable.length)
            mutable.enumerateAttribute(.tomeetImage, in: fullRange) { value, range, _ in
                guard let payload = value as? BookImagePayload,
                      let attachment = mutable.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
                else { return }
                let target = attachment.bounds.size
                let maxPixel = max(target.width, target.height) * (UIScreen.current?.scale ?? 2)
                attachment.image = BookImageLoader.image(
                    for: payload.ref,
                    baseURL: payload.baseURL,
                    maxPixelSize: maxPixel
                )
            }
            return mutable
        }

        /// 命中测试：`point` 用本页 view 的坐标系，返回该处的脚注锚点 id。
        ///
        /// 角标很小，指尖落点常在相邻字符上，所以命中点前后各容一个字符 ——
        /// Apple Books 的角标热区也是放宽的。
        func noterefID(at point: CGPoint) -> String? {
            guard let text = textView.attributedText, text.length > 0,
                  let range = textView.characterRange(at: point)
            else { return nil }
            let center = textView.offset(from: textView.beginningOfDocument, to: range.start)
            for index in [center, center - 1, center + 1] where index >= 0 && index < text.length {
                if let id = text.attribute(.tomeetNoteref, at: index, effectiveRange: nil) as? String {
                    return id
                }
            }
            return nil
        }
    }
}

/// 引文左侧竖线。一页上可能有零到多段引文，用一个视图一次画完，
/// 不为一根线各建一个视图 —— 页视图是复用缓存的重对象。
@MainActor
final class QuoteRuleView: UIView {
    /// 竖线矩形（本视图坐标系）。
    var rects: [CGRect] = [] {
        didSet { if rects != oldValue { setNeedsDisplay() } }
    }
    var color: UIColor = .clear {
        didSet { if color != oldValue { setNeedsDisplay() } }
    }

    override func draw(_ rect: CGRect) {
        guard !rects.isEmpty else { return }
        color.setFill()
        for rule in rects {
            UIBezierPath(rect: rule).fill()
        }
    }
}

// 点击分区翻页（TapZone）已移除：点击只切换悬浮菜单，翻页只由滑动触发。
