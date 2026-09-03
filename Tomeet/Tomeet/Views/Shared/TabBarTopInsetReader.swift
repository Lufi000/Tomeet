import SwiftUI
import UIKit

/// Tab 内容的底部留白：悬浮胶囊高度，播放条出现时再加播放条高度。
/// 由 RootView 实测后注入，Home/Library 的滚动容器用它做 safeAreaInset。
private struct TabContentBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabContentBottomInset: CGFloat {
        get { self[TabContentBottomInsetKey.self] }
        set { self[TabContentBottomInsetKey.self] = newValue }
    }
}

/// 实测 TabBar 胶囊顶边到安全区底边的距离（pt），写入 `inset`。
/// iOS 26 悬浮 TabBar 不吃 safeAreaInset，迷你播放条要靠实测帧垫到胶囊上方。
/// 参照系是 window 的安全区，与自身布局无关——避免"inset 改变布局反过来影响测量"的反馈环。
struct TabBarTopInsetReader: UIViewRepresentable {
    @Binding var inset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(inset: $inset)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        // 等本 view 挂上 window 后才能在层级里找到 UITabBar
        DispatchQueue.main.async {
            context.coordinator.startObserving(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator {
        private let inset: Binding<CGFloat>
        private var observation: NSKeyValueObservation?

        init(inset: Binding<CGFloat>) {
            self.inset = inset
        }

        func startObserving(from view: UIView) {
            guard let window = view.window,
                  let tabBar = window.firstSubview(of: UITabBar.self) else { return }
            // 悬浮胶囊是 UITabBar 的 _UITabBarPlatterView 子view（按类名找，不链接私有类型）；
            // 找不到（非悬浮样式/未来 iOS）就退回 UITabBar 本身
            let target = tabBar.firstSubview(named: "_UITabBarPlatterView") ?? tabBar
            observation = target.observe(\.frame, options: [.initial, .new]) { [weak self] target, _ in
                guard let self, let window = target.window else { return }
                let capsuleTop = window.convert(
                    CGPoint(x: target.bounds.midX, y: target.bounds.minY),
                    from: target
                ).y
                let safeAreaBottom = window.bounds.maxY - window.safeAreaInsets.bottom
                self.inset.wrappedValue = max(0, safeAreaBottom - capsuleTop)
            }
        }
    }
}

private extension UIView {
    /// 深度优先找层级里第一个指定类型的 view。
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let found = subview.firstSubview(of: type) { return found }
        }
        return nil
    }

    /// 深度优先找类名匹配的子view（用于不链接私有 UIKit 类型的场景）。
    func firstSubview(named className: String) -> UIView? {
        for subview in subviews {
            if String(describing: type(of: subview)) == className { return subview }
            if let found = subview.firstSubview(named: className) { return found }
        }
        return nil
    }
}
