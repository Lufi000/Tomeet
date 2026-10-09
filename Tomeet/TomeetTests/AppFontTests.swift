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

    /// **这条才是 spec §3.5 真正要的那道闸。**
    ///
    /// 上面两条断言的是**平台**能做什么 —— `Font.app` 改成任何别的东西，
    /// 它们都照样绿。而本轮最大的教训正是「换错字体不报错，只静默回落」：
    /// 把 `Font.app` 写成 `Font.custom("SFCompactRounded-Bold", size: 17)`，
    /// 全 App 会变成 Helvetica，**243 条测试一条都不会红**。
    ///
    /// SwiftUI 的 `Font` 无法反查成 `UIFont`；改成 `Font(uiFont)` 那条路
    /// 会牺牲 Dynamic Type，代价比收益大。所以直接扫**工厂的源码** ——
    /// 本仓库已有同类做法（`DesignSystemGuardTests` 也是扫源码的）。
    @Test func appFontFactoryStaysOnTheRoundedSystemDesign() throws {
        let factory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TomeetTests
            .deletingLastPathComponent()   // Tomeet
            .appendingPathComponent("Tomeet/Theme/AppFont.swift")
        let source = try String(contentsOf: factory, encoding: .utf8)

        #expect(source.contains("design: .rounded"),
                "Font.app 不再走 .rounded —— 圆体方案被改掉了")

        #expect(!source.contains("Font.custom("),
                """
                Font.app 用了 Font.custom。它**找不到字体时不抛错也不返回 nil**，\
                会静默给你 Helvetica —— 实测：设计稿指定的 .SFCompactRounded-Bold \
                就是这么回落到 Times New Roman / Helvetica 的。
                """)

        #expect(!source.contains(".system(size:"),
                "Font.app 用了固定字号，会丢掉 Dynamic Type")
    }
}
