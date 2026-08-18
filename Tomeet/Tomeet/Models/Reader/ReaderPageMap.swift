import Foundation

/// 全局书页位置：第几章 + 章内第几页。
struct PageRef: Sendable, Equatable {
    let chapterIndex: Int
    let pageInChapter: Int
}

/// 全局页量 ↔ (章节, 章内页) 与 章节内字符偏移 ↔ 页 的纯映射表。
/// 由分页结果一次性构建，全权只读。
struct ReaderPageMap: Sendable {
    let chapterPages: [PaginatedChapter]

    /// `chapterStartPage[i]` = 第 i 章首页的全局页索引；`count == chapterPages.count + 1`，末位为总页数。
    let chapterStartPage: [Int]

    init(chapterPages: [PaginatedChapter]) {
        self.chapterPages = chapterPages
        var starts: [Int] = [0]
        for chapter in chapterPages {
            starts.append(starts[starts.count - 1] + chapter.pages.count)
        }
        self.chapterStartPage = starts
    }

    var totalPages: Int { chapterStartPage.last ?? 0 }

    func globalIndex(pageRef: PageRef) -> Int? {
        guard chapterPages.indices.contains(pageRef.chapterIndex) else { return nil }
        let pages = chapterPages[pageRef.chapterIndex].pages
        guard pageRef.pageInChapter >= 0 && pageRef.pageInChapter < pages.count else { return nil }
        return chapterStartPage[pageRef.chapterIndex] + pageRef.pageInChapter
    }

    func pageRef(globalIndex: Int) -> PageRef? {
        guard globalIndex >= 0, globalIndex < totalPages else { return nil }
        // 找最后一个 chapterStartPage[i] <= globalIndex 的 i
        var chapter = 0
        for index in 0..<chapterPages.count where chapterStartPage[index] <= globalIndex {
            chapter = index
        }
        return PageRef(chapterIndex: chapter, pageInChapter: globalIndex - chapterStartPage[chapter])
    }

    func textPage(globalIndex: Int) -> TextPage? {
        guard let ref = pageRef(globalIndex: globalIndex) else { return nil }
        let pages = chapterPages[ref.chapterIndex].pages
        return pages.indices.contains(ref.pageInChapter) ? pages[ref.pageInChapter] : nil
    }

    /// 找到包含章节内字符偏移的页；偏移等于章尾（文本长度）回落最后一页。
    func pageRef(chapterIndex: Int, charOffset: Int) -> PageRef? {
        guard chapterPages.indices.contains(chapterIndex) else { return nil }
        let pages = chapterPages[chapterIndex].pages
        guard !pages.isEmpty else { return nil }
        for (index, page) in pages.enumerated() {
            let end = page.characterRange.location + page.characterRange.length
            if page.characterRange.location <= charOffset && charOffset < end {
                return PageRef(chapterIndex: chapterIndex, pageInChapter: index)
            }
        }
        if charOffset == pages.last.map({ $0.characterRange.location + $0.characterRange.length }) {
            return PageRef(chapterIndex: chapterIndex, pageInChapter: pages.count - 1)
        }
        return nil
    }
}
