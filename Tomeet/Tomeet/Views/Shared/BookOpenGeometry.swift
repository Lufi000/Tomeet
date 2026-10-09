import CoreGraphics
import Foundation

/// 「翻开一本书」的两拍插值。
///
/// 一条进度 `t` 驱动两拍，进入 / 退出共用同一条路径（与 `UnreadBookPeekView` 同一种写法）：
///
/// - **抬起**（t: 0 → `liftEnd`）：封面从书架那一格的原位与原始尺寸，移到屏幕正中、
///   放大到「书」的大小。t = 0 那一帧与书架上被点的那张封面逐像素重合，所以
///   呈现层插进来的第一帧不跳。
/// - **翻开**（t: `turnStart` → 1）：封面绕**左边缘（书脊）**转到侧立（-90°）。
///   起点**早于**抬起的终点：两拍各自用 smoothstep，导数在各自的端点是 0，
///   首尾相接就会「减速到停、再重新加速」——那正是卡顿感的来源。咬合之后，
///   任何一帧至少有一个分量在动。
///
/// 转角**到侧立为止**，不再往下：过了 -90° 封面会镜像着从书脊左边重新长出来 ——
/// 表现就是「一块反着的封面」一直赖在屏幕左边。所以收场交给几何（转到侧立即投影
/// 宽度归零），不靠淡出；封面全程不透明。
///
/// 封面宽度在翻开时会一起长到铺满画布高度（`bookHeightRatio`），一是「书凑近了」，
/// 二是书脊必须移出屏幕左边 —— 否则转到侧立时左边缘会残留一条。
struct BookOpenGeometry {
    /// 这一帧封面摆在哪、转多少度，底下两层各该多显眼。
    struct Pose {
        var center: CGPoint
        /// 封面**未旋转**的宽度。高度按 2:3 导出，与 `BookCoverView` 一致。
        var width: CGFloat
        var height: CGFloat { width * 3 / 2 }
        /// 绕左边缘（书脊）的旋转角，0 … -90。
        var angle: Double
        /// 封面被「拿起来」的进度：0 = 还贴在书架上，1 = 已经悬在屏幕中央。
        /// 投影靠它淡入。
        var lift: Double
        /// 底下那层阅读器的透明度。
        var readerOpacity: Double
        /// 压暗书架的那层。
        var backdropDim: Double
    }

    /// 被点封面在全局坐标系中的矩形；nil = 没有原位（冷启动自动续读、cell 已滚出屏幕）。
    let source: CGRect?
    /// 全屏画布尺寸。必须与 `source` 同一坐标系（都用 `.ignoresSafeArea()` 之后的全屏）。
    let canvas: CGSize

    // MARK: - 刻度

    /// 抬起拍的结束点：封面此刻正好居中、放大到书本大小。
    static let liftEnd: Double = 0.45
    /// 封面开始绕书脊转的时刻。**故意早于 `liftEnd`** —— 两拍咬合，中途才不会出现
    /// 「所有分量同时静止」的一帧。见 `theTwoBeatsOverlap` 与 `motionNeverStallsBeforeTheEnd`。
    static let turnStart: Double = 0.34
    /// 抬起后封面宽度占画布宽度的比例。
    static let bookWidthRatio: CGFloat = 0.72
    /// 翻开时封面长到的高度占画布高度的比例；宽度由它按 2:3 反推。
    static let bookHeightRatio: CGFloat = 0.94
    /// 封面长到最终尺寸占翻开拍的比例。
    static let growSpan: Double = 0.35
    /// 阅读器淡入的窗口（绝对进度）。必须在 `liftEnd` 之前结束 ——
    /// 见 `readerIsFullyOpaqueBeforeTheCoverStartsOpening`。
    static let readerFadeStart: Double = 0.22
    static let readerFadeEnd: Double = 0.44
    /// 背板压暗到位占抬起拍的比例。
    static let dimEnd: Double = 0.36
    /// 3D 透视强度，越大近大远小越强。比 `UnreadBookPeekView` 略强：那是一张卡片翻过来，
    /// 这里是一页纸绕着书脊荡开，透视弱了会像平面贴图在横向缩放。
    static let perspective: Double = 0.6

    var isAnimated: Bool { source != nil }

    // MARK: - 插值

    func pose(at rawProgress: Double) -> Pose {
        let t = min(max(rawProgress, 0), 1)
        guard let source else {
            // 不动画：直接返回终态，调用方按 `isAnimated` 决定要不要用。
            return Pose(center: canvasCenter, width: openWidth, angle: -90, lift: 1, readerOpacity: 1, backdropDim: 1)
        }

        let lift = Self.smoothstep(min(t / Self.liftEnd, 1))
        // 宽度在抬起之后接着长到铺满；转角则**提前**起跑，和抬起咬合。
        let grow = Self.smoothstep(min(
            Self.clamp01((t - Self.liftEnd) / ((1 - Self.liftEnd) * Self.growSpan)), 1
        ))
        let turn = Self.smoothstep(Self.clamp01((t - Self.turnStart) / (1 - Self.turnStart)))

        return Pose(
            center: CGPoint(
                x: Self.lerp(source.midX, canvasCenter.x, lift),
                y: Self.lerp(source.midY, canvasCenter.y, lift)
            ),
            width: Self.lerp(Self.lerp(source.width, liftedWidth, lift), openWidth, grow),
            angle: -90 * turn,
            lift: lift,
            readerOpacity: Self.readerOpacity(at: t),
            backdropDim: Self.backdropDim(at: t)
        )
    }

    /// 阅读器的浓淡。**不依赖画布** —— 呈现层要在 GeometryReader 之外也用它
    /// （阅读器不能放进 ignore 安全区的那层，否则它算不到正确的分页内衬），
    /// 而那里量不到全屏尺寸。
    static func readerOpacity(at rawProgress: Double) -> Double {
        smoothstep(clamp01(
            (clamp01(rawProgress) - readerFadeStart) / (readerFadeEnd - readerFadeStart)
        ))
    }

    /// 背板压暗的浓淡。同样不依赖画布。
    static func backdropDim(at rawProgress: Double) -> Double {
        smoothstep(min(clamp01(rawProgress) / dimEnd, 1))
    }

    // MARK: - 尺寸

    private var canvasCenter: CGPoint {
        CGPoint(x: canvas.width / 2, y: canvas.height / 2)
    }

    private var liftedWidth: CGFloat {
        canvas.width * Self.bookWidthRatio
    }

    /// 翻开后的宽度：先按「封面高度铺满画布的 `bookHeightRatio`」算，但不窄于画布本身 ——
    /// 书脊（旋转锚点 = 封面左边缘）必须在屏幕外，否则转到侧立时左边缘残留一条。
    private var openWidth: CGFloat {
        max(canvas.height * Self.bookHeightRatio * 2 / 3, canvas.width)
    }

    // MARK: - 小工具

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// 两端一阶导为 0 的平滑插值。比线性多一口气，又不像弹簧那样需要担心过冲 ——
    /// 过冲在这里是穿帮：封面冲过头会把书脊甩到屏幕右边去。
    private static func smoothstep(_ x: Double) -> Double {
        let c = clamp01(x)
        return c * c * (3 - 2 * c)
    }
}
