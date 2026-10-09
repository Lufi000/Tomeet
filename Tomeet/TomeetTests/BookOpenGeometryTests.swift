import CoreGraphics
import Testing
@testable import Tomeet

/// 「翻开一本书」的两拍插值。这里只测纯几何 —— 动效好不好看要用眼睛看（录屏），
/// 但「起手那一帧有没有和书架封面严丝合缝」「翻开时底下是不是已经完全不透明」
/// 这类事是算得出来的，算得出来的就不该靠眼睛。
struct BookOpenGeometryTests {
    private let canvas = CGSize(width: 393, height: 852)
    /// 书架上被点的那一格：2:3，落在网格里、不在屏幕正中。
    private let source = CGRect(x: 24, y: 300, width: 168, height: 252)

    private var geometry: BookOpenGeometry {
        BookOpenGeometry(source: source, canvas: canvas)
    }

    @Test func noSourceFrameMeansNoAnimation() {
        #expect(BookOpenGeometry(source: nil, canvas: canvas).isAnimated == false)
        #expect(geometry.isAnimated == true)
    }

    @Test func firstFrameSitsExactlyOnTheShelfCover() {
        let pose = geometry.pose(at: 0)
        #expect(pose.center == CGPoint(x: source.midX, y: source.midY))
        #expect(pose.width == source.width)
        #expect(pose.height == source.height)
    }

    @Test func firstFrameIsSquareOnAndTheReaderIsInvisible() {
        let pose = geometry.pose(at: 0)
        #expect(pose.angle == 0)
        #expect(pose.readerOpacity == 0)
        #expect(pose.backdropDim == 0)
    }

    @Test func liftEndsWithTheCoverCentredAtBookSize() {
        let pose = geometry.pose(at: BookOpenGeometry.liftEnd)
        #expect(pose.center.x == canvas.width / 2)
        #expect(pose.center.y == canvas.height / 2)
        #expect(pose.width == canvas.width * BookOpenGeometry.bookWidthRatio)
    }

    @Test func coverStaysSquareOnUntilTheTurnBegins() {
        #expect(geometry.pose(at: BookOpenGeometry.turnStart - 0.001).angle == 0)
    }

    /// 两拍必须**咬合**，不能一拍停稳了再起第二拍。
    ///
    /// 两个 smoothstep 首尾相接时，各自的导数在接缝处都是 0 —— 观感就是
    /// 「抬起 → 顿一下 → 荡开」，正是实测到的那一下卡顿。
    @Test func theTwoBeatsOverlap() {
        #expect(BookOpenGeometry.turnStart < BookOpenGeometry.liftEnd)
        #expect(geometry.pose(at: BookOpenGeometry.liftEnd + 0.05).angle < 0)
    }

    /// 全程没有任何一帧"什么都么没动"。有，就是一次可见的停顿。
    @Test func motionNeverStallsBeforeTheEnd() {
        var previous = geometry.pose(at: 0)
        for step in 1...80 {
            let pose = geometry.pose(at: Double(step) / 80)
            let delta = abs(pose.angle - previous.angle)
                + Double(abs(pose.width - previous.width))
                + hypot(pose.center.x - previous.center.x, pose.center.y - previous.center.y)
            #expect(delta > 1e-9)
            previous = pose
        }
    }

    /// 过了侧立（-90°）封面会镜像着从左边重新长出来 —— 那正是「一块反着的封面」
    /// 一直赖在屏幕上。所以转角到侧立为止，靠几何收场，不靠淡出。
    @Test func coverNeverSwingsPastEdgeOn() {
        for step in 0...40 {
            let pose = geometry.pose(at: Double(step) / 40)
            #expect(pose.angle >= -90)
        }
    }

    @Test func rotationNeverBacksUp() {
        var previous = 0.0
        for step in 0...60 {
            let angle = geometry.pose(at: Double(step) / 60).angle
            #expect(angle <= previous)
            previous = angle
        }
    }

    @Test func coverIsEdgeOnAndOffScreenAtTheEnd() {
        let pose = geometry.pose(at: 1)
        let projected = pose.width * abs(cos(pose.angle * .pi / 180))
        #expect(projected < 0.5)
        // 书脊（旋转锚点 = 封面左边缘）也必须已经出了屏幕，否则左边缘会留一条
        #expect(pose.center.x - pose.width / 2 <= 0)
    }

    /// 封面翻开的那一瞬，底下露出来的必须是**最终的**阅读器。半透明地被揭开
    /// 会露出压在底下的书架，就是一闪。
    @Test func readerIsFullyOpaqueBeforeTheCoverStartsOpening() {
        for step in 0...20 {
            let pose = geometry.pose(at: BookOpenGeometry.liftEnd + Double(step) / 20 * (1 - BookOpenGeometry.liftEnd))
            #expect(pose.readerOpacity == 1)
        }
    }

    /// 封面被「拿起来」的进度：投影靠它淡入 —— 没有投影，封面看着就是贴在背景上的。
    @Test func liftIsZeroAtStartAndSettledOnceTheCoverIsUp() {
        #expect(geometry.pose(at: 0).lift == 0)
        #expect(geometry.pose(at: BookOpenGeometry.liftEnd).lift == 1)
        #expect(geometry.pose(at: 1).lift == 1)
    }

    @Test func readerFadesInDuringTheLift() {
        let halfway = geometry.pose(at: BookOpenGeometry.liftEnd * 0.78).readerOpacity
        #expect(halfway > 0 && halfway < 1)
    }

    /// 阅读器浓淡的独立入口必须和 `pose` 里那一个严丝合缝：呈现层在 GeometryReader
    /// **之外**读它（阅读器不能放进 ignore 安全区的那层），两处一旦漂移，
    /// 阅读器的淡入就会和封面错开。
    @Test func fadeEntryPointsAgreeWithPose() {
        for step in 0...40 {
            let t = Double(step) / 40
            #expect(BookOpenGeometry.readerOpacity(at: t) == geometry.pose(at: t).readerOpacity)
            #expect(BookOpenGeometry.backdropDim(at: t) == geometry.pose(at: t).backdropDim)
        }
    }

    @Test func progressIsClampedAtBothEnds() {
        #expect(geometry.pose(at: -1).readerOpacity == 0)
        #expect(geometry.pose(at: 2).angle == -90)
    }
}
