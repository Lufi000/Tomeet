import SwiftData
import SwiftUI

/// 「打开一本书」的全局呈现状态。
///
/// 阅读器不再走 `fullScreenCover`。理由不是偏好，是两条硬约束：
/// 那套升起动画是 UIKit 的、换不掉；而「封面从书架原位抬起 → 翻开 → 底下露出正文」
/// 要求**书架留在后面可见**、且**阅读器已经在封面下面** —— 这两条 `fullScreenCover`
/// 都给不了（被推上来的是一整块，封面会跟着它一起从屏幕底部升起来）。
///
/// 所以改由 `RootView` 最外层的一块呈现层接管。放在 TabView 之上还顺带解决了 TabBar：
/// 整层盖在 TabView 上，TabBar 自然被盖住，不用再 `.toolbar(.hidden, for: .tabBar)`。
@MainActor
@Observable
final class BookOpening {
    struct Request: Identifiable {
        let book: Book
        /// 被点封面在全局坐标系中的位置。nil = 没有原位（冷启动自动续读、cell 已滚出
        /// 屏幕、从 Home 轮播打开），此时不演动效 —— 凭空从屏幕中央长出一张封面，
        /// 比直接出现更怪。
        let sourceFrame: CGRect?
        var id: UUID { book.id }
    }

    private(set) var request: Request?

    func open(_ book: Book, from sourceFrame: CGRect?) {
        request = Request(book: book, sourceFrame: sourceFrame)
    }

    func finish() {
        request = nil
    }

    /// 书在别处被删掉时收掉呈现层，免得继续拿着一个失效的 SwiftData 对象。
    func closeIfDeleted(existingIDs: Set<UUID>) {
        if let request, !existingIDs.contains(request.book.id) {
            self.request = nil
        }
    }
}

/// 由呈现层注入的「合上这本书」：先播合书动效，再拆掉整层。
///
/// 三个阅读器（`ReaderView` / `PDFReaderView` / `MobiReaderView`）原来各自
/// `@Environment(\.dismiss)`。这里**不用**去覆盖系统的 `\.dismiss`（`DismissAction`
/// 没有公开构造器），而是另开一个值；没被注入时调用方退回 `dismiss`。
private struct BookCloseKey: EnvironmentKey {
    static var defaultValue: (() -> Void)?
}

extension EnvironmentValues {
    var bookClose: (() -> Void)? {
        get { self[BookCloseKey.self] }
        set { self[BookCloseKey.self] = newValue }
    }
}

/// 关掉当前这本书：经过呈现层时走注入的合书动效（先合上，再拆层），
/// 直接 present 时退回系统 `dismiss`。
///
/// 写成自由函数而不是 `EnvironmentValues` 的扩展：视图里 `@Environment` 只给得到
/// 单个 key 的**值**，拿不到整个 `EnvironmentValues` 容器，方法无处可调。
@MainActor
func closeBook(_ bookClose: (() -> Void)?, orDismiss dismiss: DismissAction) {
    if let bookClose { bookClose() } else { dismiss() }
}

