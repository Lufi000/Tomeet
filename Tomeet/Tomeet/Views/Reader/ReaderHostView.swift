import SwiftUI
import UIKit

/// UIPageViewController .pageCurl 翻页桥。
struct ReaderHostView: UIViewControllerRepresentable {
    let viewModel: ReaderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
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
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.reconcile(pageViewController)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var viewModel: ReaderViewModel
        weak var pageViewController: UIPageViewController?
        private var pages: [Int: UIViewController] = [:]
        private var shownGlobalIndex: Int?

        init(viewModel: ReaderViewModel) {
            self.viewModel = viewModel
        }

        func reconcile(_ pageViewController: UIPageViewController) {
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
            let pageVC = ReaderPageVC()
            pageVC.configure(text: text)
            pages[index] = pageVC
            return pageVC
        }

        private func trimCache(around index: Int) {
            for key in pages.keys where abs(key - index) > 4 {
                pages.removeValue(forKey: key)
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
    @MainActor
    final class ReaderPageVC: UIViewController {
        private let textView = UITextView()

        override func loadView() {
            textView.isEditable = false
            textView.isSelectable = false
            textView.isScrollEnabled = false
            textView.backgroundColor = .black
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            view = textView
        }

        func configure(text: TextPage) {
            textView.attributedText = text.text
        }
    }
}
