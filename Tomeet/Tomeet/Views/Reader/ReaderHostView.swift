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
            guard viewModel.phase == .ready else { return }
            let target = viewModel.currentGlobalIndex
            guard target >= 0, target < viewModel.totalPages else { return }
            if shownGlobalIndex != target {
                let animated = abs(target - (shownGlobalIndex ?? 0)) == 1
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
            let horizontalInset = CGFloat(viewModel.settings?.horizontalMargin ?? 28)
            let verticalInset = CGFloat(viewModel.settings?.verticalMargin ?? 36)
            let pageVC = ReaderPageVC(theme: theme, horizontalInset: horizontalInset, verticalInset: verticalInset)
            pageVC.configure(text: text)
            pages[index] = pageVC
            return pageVC
        }

        private func trimCache(around index: Int) {
            for key in pages.keys where abs(key - index) > 4 {
                pages.removeValue(forKey: key)
            }
        }

        // MARK: - Tap zones

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            let zone = TapZone.zone(for: location, in: view.bounds)
            switch zone {
            case .previous:
                turnPage(forward: false)
            case .next:
                turnPage(forward: true)
            case .center:
                onToggleChrome?()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // 点击等待滑动手势失败后再响应，确保翻页滑动优先。
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        private func turnPage(forward: Bool) {
            guard let pageViewController,
                  let current = pageViewController.viewControllers?.first,
                  let index = index(of: current)
            else { return }
            let target = forward ? index + 1 : index - 1
            guard target >= 0, target < viewModel.totalPages else { return }
            guard let controller = page(for: target) else { return }
            pageViewController.setViewControllers(
                [controller],
                direction: forward ? .forward : .reverse,
                animated: true
            ) { [weak self] _ in
                self?.shownGlobalIndex = target
                self?.viewModel.settle(globalIndex: target)
            }
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

    /// 单页：禁选禁滚动的 UITextView，只承载排版好的 attributed text。
    /// 分页时正文宽度 = 屏宽 - 2*horizontalInset（ChapterPager），渲染时再用
    /// textContainerInset 留出同宽边距，文字块恰好居中且不换行错位。
    @MainActor
    final class ReaderPageVC: UIViewController {
        private let textView = UITextView()
        private let theme: ReaderTheme
        private let horizontalInset: CGFloat
        private let verticalInset: CGFloat

        init(theme: ReaderTheme, horizontalInset: CGFloat = 28, verticalInset: CGFloat = 36) {
            self.theme = theme
            self.horizontalInset = horizontalInset
            self.verticalInset = verticalInset
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            self.theme = .original
            self.horizontalInset = 28
            self.verticalInset = 36
            super.init(coder: coder)
        }

        override func loadView() {
            textView.isEditable = false
            textView.isSelectable = false
            textView.isScrollEnabled = false
            textView.backgroundColor = UIColor(theme.backgroundColor)
            // 文字颜色由 NSAttributedString 携带的主题色/强调色控制。
            textView.textContainerInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
            textView.textContainer.lineFragmentPadding = 0
            view = textView
        }

        func apply(theme: ReaderTheme) {
            textView.backgroundColor = UIColor(theme.backgroundColor)
        }

        func configure(text: TextPage) {
            textView.attributedText = text.text
        }
    }
}

// MARK: - Tap zone

enum TapZone {
    case previous, center, next

    static func zone(for location: CGPoint, in bounds: CGRect) -> TapZone {
        let x = location.x / bounds.width
        if x < 0.30 { return .previous }
        if x > 0.70 { return .next }
        return .center
    }
}
