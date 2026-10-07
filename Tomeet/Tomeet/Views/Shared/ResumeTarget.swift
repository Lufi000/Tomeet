import Foundation

/// 启动时「回到在读的那一页」要打开哪本书。
enum ResumeTarget {
    /// 最近打开、并且存得下阅读位置的那本；没有就返回 nil。
    ///
    /// 判据用 `currentLocation` 而不是 `lastOpenedDate`：
    /// 打开过不等于读到过（点开又退出、或者只有 PDF/MOBI 这类没有字符位置的格式），
    /// 拿它当依据会把用户丢进一本停在第一页的书里 —— 那比不自动进更烦人。
    static func book(in books: [Book]) -> Book? {
        books
            .filter(isResumable)
            .sorted(by: Book.sortRecentlyOpened)
            .first
    }

    /// 存了**能解析**的阅读位置才算可续读。编码坏掉的书（旧版本写坏的字段）不能拦住启动。
    private static func isResumable(_ book: Book) -> Bool {
        guard let encoded = book.currentLocation else { return false }
        return ReaderLocation(encoded: encoded) != nil
    }
}
