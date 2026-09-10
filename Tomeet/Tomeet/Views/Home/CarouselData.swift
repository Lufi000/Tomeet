import Foundation

/// 轮播数据源:最近在读(lastOpenedDate 倒序)在前,其余书按标题排序在后。
enum CarouselData {
    static func books(_ all: [Book]) -> [Book] {
        let recent = all.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
        let rest = all.filter { $0.lastOpenedDate == nil }
            .sorted { $0.title < $1.title }
        return recent + rest
    }
}
