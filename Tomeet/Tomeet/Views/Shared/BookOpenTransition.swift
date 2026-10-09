import SwiftUI

/// 动效刻度。和 `UnreadBookPeekView` 里的 `Peek` 一样集中放一处：
/// `shadow(radius:)` / `blur(radius:)` 这类数值不属于圆角刻度，硬套 `Radius` 令牌
/// 只会让门禁闭嘴、却把语义写错。给它们一个有名字的家，既不裸奔又不说谎。
private enum Open {
    /// 整段翻开的曲线 —— 抬起和荡开跑的是**同一次运动**，中间不停。
    /// 比原来分段的曲线长一点：一条曲线里 `t` 前段走得快，抬起那一拍实际只占约三分之一。
    static let open: Animation = .spring(response: 0.62, dampingFraction: 0.92)
    /// 合书用的曲线。和 `open` 同一条：倒着走回去时才不会走样。
    static let close: Animation = open
    /// 合书动画播完到拆层的等待。比曲线沉降久一点，早了会在半空把层拆掉。
    static let settleMilliseconds: Int = 900
    /// 「减弱动效」下的交叉淡入时长（秒）。
    static let fadeSeconds: Double = 0.2

    /// 封面投影的模糊半径与下移量。抬起时淡入 —— 没有投影，封面看着就是贴在背景上的。
    static let coverShadow: CGFloat = 24
    static let coverShadowY: CGFloat = 8
    /// 背板压暗浓度。比未读弹层轻：那里要盖住整个书架，这里封面自己就是主角。
    static let backdropDim: Double = 0.22
}

/// 「翻开一本书」的全屏呈现层。
///
/// 自下而上三层：压暗的书架 → 阅读器 → 封面。运动全部由 `BookOpenGeometry` 一条进度 `t`
/// 算出来，进入与退出共用同一条路径（退出就是 `t` 倒着走回 0）。
struct BookOpenTransition: View {
    let request: BookOpening.Request
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 形态进度：0 = 封面还贴在书架上，1 = 书已翻开、阅读器满屏。
    @State private var t: Double = 0
    /// 只在「不演动效」时参与：那时不画封面，只把阅读器交叉淡入。
    @State private var fade: Double = 1
    @State private var didStartClosing = false

    /// 有没有原位坐标可演。开了「减弱动效」就当作没有 —— 一页纸绕着书脊荡开，
    /// 正是这类动画最该被关掉的样子。
    private var isAnimated: Bool {
        request.sourceFrame != nil && !reduceMotion
    }

    var body: some View {
        ZStack {
            // 1. 压暗书架。**必须在阅读器之下** —— 它上面只该盖封面。
            //    画在阅读器之上会把正文一起压灰：t=1 之后那层黑不会自己走开，
            //    整页阅读器就永远蒙着一层 22% 的纱。
            Theme.solidInk
                .opacity(isAnimated ? Open.backdropDim * BookOpenGeometry.backdropDim(at: t) : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 2. 阅读器。**不** ignore 安全区：它内部按 `proxy.safeAreaInsets` 算分页内衬，
            //    在这一层把安全区吃掉，正文就会排到灵动岛和 Home 指示条底下。
            BookReaderPresenter.view(for: request.book)
                .environment(\.bookClose, { close() })
                .opacity(isAnimated ? BookOpenGeometry.readerOpacity(at: t) : fade)

            // 3. 封面。要的是**整屏**坐标：`sourceFrame` 是全局坐标系的，
            //    画布必须是整屏，两者才对得上。
            if isAnimated {
                GeometryReader { proxy in
                    let pose = BookOpenGeometry(source: request.sourceFrame, canvas: proxy.size).pose(at: t)
                    cover(pose)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .task { await run() }
    }

    private func cover(_ pose: BookOpenGeometry.Pose) -> some View {
        BookCoverView(book: request.book)
            .frame(width: pose.width, height: pose.height)
            .shadow(
                color: Theme.solidInk.opacity(0.3 * pose.lift),
                radius: Open.coverShadow,
                y: Open.coverShadowY
            )
            // 转轴是封面左边缘 = 书脊。必须挂在 `position` **之前**：`position` 会把自身的
            // 布局框撑成整屏，之后再挂旋转，转的就不是书脊而是屏幕左边缘了。
            .rotation3DEffect(
                .degrees(pose.angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: BookOpenGeometry.perspective
            )
            .position(pose.center)
    }

    // MARK: - 进度

    private func run() async {
        guard isAnimated else {
            // 没有原位、或开了「减弱动效」：不画封面，只把阅读器淡进来。
            fade = 0
            t = 1
            withAnimation(.easeOut(duration: Open.fadeSeconds)) { fade = 1 }
            return
        }

        // 一条曲线跑到底：抬起与荡开是**同一次运动**的两段。
        //
        // 中途**不能**停下来等阅读器就绪。等一下就是一次肉眼可见的卡顿，
        // 而阅读器首屏实测要 ~9 秒（解析 + 分页），等了底下照样是转圈 ——
        // 白白拿一次停顿去换一个并没有变好的画面。
        withAnimation(Open.open) { t = 1 }
    }

    /// 合书：`t` 倒着走回 0，封面沿来路落回书架那一格。
    private func close() {
        guard !didStartClosing else { return }
        didStartClosing = true
        let settle = isAnimated ? Open.settleMilliseconds : Int(Open.fadeSeconds * 1000) + 50
        if isAnimated {
            withAnimation(Open.close) { t = 0 }
        } else {
            withAnimation(.easeOut(duration: Open.fadeSeconds)) { fade = 0 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(settle))
            onFinished()
        }
    }
}
