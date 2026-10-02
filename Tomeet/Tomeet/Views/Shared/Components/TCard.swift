import SwiftUI

extension View {
    /// 卡片容器：`Theme.card` 填充 + 统一圆角 + `.continuous` 风格。
    ///
    /// 三者绑定成一处，消灭原先「圆角在 background 写一遍、在 clipShape 又写一遍」
    /// 导致改一处漏一处的问题（原 `NowPlayingBar.swift:56` 与 `:63`）。
    func tCard(radius: CGFloat = Radius.md) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Theme.card))
            .clipShape(shape)
    }
}
