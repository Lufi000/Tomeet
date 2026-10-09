import SwiftUI
import Testing
@testable import Tomeet

/// 钉住「`.design(.rounded)` 背后真的是一支圆体」。
///
/// **这两条是平台契约的回归守卫，不是 TDD 意义上的红→绿测试** ——
/// 它们按构造就不可能先红：测的是系统行为，不是本轮要写的代码。
/// Task 1 真正的红→绿在 `TextRoleTests` 的编译失败→通过那一段。
///
/// 价值不在今天（`.design(.rounded)` 是公开 API，坏不了），而在**拦住未来**：
/// 字体一旦被改成 `Font.custom` 之类的写法，找不到字体会静默回落到系统默认 ——
/// 界面看着正常，字形全错，没有任何测试会红。
/// 实测过这条坑：`.SFCompactRounded-Bold` 回落到 Times New Roman，
/// 不带点的 `SFCompactRounded-Bold` 回落到 Helvetica。
struct AppFontTests {
    @Test func roundedDesignResolvesToARoundedFace() throws {
        let base = UIFont.systemFont(ofSize: 17, weight: .bold)
        let descriptor = try #require(
            base.fontDescriptor.withDesign(.rounded),
            "系统不再提供 rounded design —— 圆体方案的前提没了"
        )
        let resolved = UIFont(descriptor: descriptor, size: 17)
        #expect(resolved.fontName.localizedCaseInsensitiveContains("Rounded"),
                "解析出来的是 \(resolved.fontName)，不是圆体")
    }

    /// 防呆：上一条只证明「系统里有圆体」。
    /// 这一条证明**圆体和衬线确实是两支不同的字体** ——
    /// 否则即使实现里写错了 design，上一条也会绿。
    @Test func roundedAndSerifAreDifferentFaces() throws {
        let base = UIFont.systemFont(ofSize: 17, weight: .regular)
        let rounded = try #require(base.fontDescriptor.withDesign(.rounded))
        let serif = try #require(base.fontDescriptor.withDesign(.serif))
        let roundedName = UIFont(descriptor: rounded, size: 17).fontName
        let serifName = UIFont(descriptor: serif, size: 17).fontName
        #expect(roundedName != serifName, "圆体和衬线解析到了同一支字体，设计没生效")
    }
}
