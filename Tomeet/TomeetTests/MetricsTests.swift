import Foundation
import Testing
@testable import Tomeet

struct MetricsTests {
    @Test func spacingIsStrictlyAscendingWithNoDuplicates() {
        let values = Spacing.all
        #expect(values == values.sorted(), "刻度必须严格递增，\(values) 顺序不对")
        #expect(Set(values).count == values.count, "刻度值不得重复：\(values)")
    }

    /// 8pt 网格是硬约束，**没有例外** —— 旧的 `hairline`(2) 已删除。
    /// 它的用途（紧贴文字堆叠）归入 `xs`(8)。
    @Test func spacingIsOnEightPointGrid() {
        for value in Spacing.all {
            #expect(value.truncatingRemainder(dividingBy: 8) == 0,
                    "\(value) 不是 8 的倍数")
        }
    }

    /// 防呆：上一条对空数组恒真 —— 刻度被清空时它会假装通过。
    @Test func spacingScaleIsNotEmpty() {
        #expect(Spacing.all.count >= 6, "刻度只剩 \(Spacing.all.count) 档，太少了")
    }

    /// 半步是全 App **唯一**的次网格值，而且必须具名。
    ///
    /// 它不在 `Spacing.all` 里（上一条因此看不见它），这正是要点：
    /// 内联的 `Spacing.xs / 2` 是**会扩散**的写法 —— 下一个页面想要半步时会照抄，
    /// 「严格 8 网格」这句话就悄悄变成假的，而套件全绿。
    /// 具名之后它只有一处，`DesignSystemGuardTests` 拦内联除法。
    @Test func halfStepIsTheOneNamedSubGridValue() {
        #expect(Spacing.halfStep == Spacing.xs / 2)
        #expect(Spacing.halfStep == 4, "半步应当是 4pt；改这里等于改角标的高度")
        #expect(!Spacing.all.contains(Spacing.halfStep),
                "半步不该混进刻度表 —— 它不是一档，是一个被计数的例外")
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
