import Foundation
import Testing
@testable import Tomeet

struct MetricsTests {
    @Test func spacingIsStrictlyAscendingWithNoDuplicates() {
        let values = Spacing.all
        #expect(values == values.sorted(), "刻度必须严格递增，\(values) 顺序不对")
        #expect(Set(values).count == values.count, "刻度值不得重复：\(values)")
    }

    @Test func spacingIsOnFourPointGridExceptHairline() {
        for value in Spacing.all where value != Spacing.hairline {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0,
                    "\(value) 不在 4pt 网格上")
        }
        #expect(Spacing.hairline == 2, "hairline 是唯一的非网格值")
    }

    @Test func radiusIsStrictlyAscendingAndOnGrid() {
        let values = Radius.all
        #expect(values == values.sorted(), "圆角刻度必须严格递增")
        #expect(Set(values).count == values.count, "圆角刻度不得重复")
        for value in Radius.all {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0,
                    "圆角 \(value) 不在 4pt 网格上")
        }
    }
}
