import SwiftUI

/// 被点书封面在全局坐标系中的位置，由书架各 cell 通过 preference 上报，
/// 供弹层做「从封面原位翻转放大」的起点。
struct BookCoverFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 弹层几何常量。
///
/// 集中在这里，是因为 `blur(radius:)` / `shadow(radius:)` 这类数值**不属于圆角刻度** ——
/// 硬套 `Radius` 令牌只会让门禁闭嘴，却把语义写错。给它们一个有名字的家，
/// 既不裸奔又不说谎。
private enum Peek {
    /// 卡片高度占可用高度的比例。留出的余量就是「压不到 TabBar / 播放条」的保证。
    static let cardHeightRatio: CGFloat = 0.72
    /// 卡片左右留白。
    static let sideInset: CGFloat = Spacing.xl
    /// hero（虚化封面底）高度占卡片高度的比例。
    static let heroRatio: CGFloat = 0.42
    /// 虚化封面底的模糊半径。要够大才会糊成一块「氛围色」，看得出封面轮廓就成了穿帮。
    static let heroBlur: CGFloat = 28
    /// 虚化底向下的渐隐：从这个比例处开始淡出。
    static let heroFadeStart: CGFloat = 0.55
    /// 详情里那张封面占卡片宽度的比例（按参考图量出来的）。
    static let coverWidthRatio: CGFloat = 0.38
    /// 封面自身投影的模糊半径。
    static let coverShadow: CGFloat = 10
    /// 卡片投影的模糊半径。
    static let cardShadow: CGFloat = 24
    /// 起手圆角。取值对齐 `BookCoverView` 内部写死的 6 —— 起手那一帧卡片正压在被点的
    /// 封面上，圆角差 2pt 就会在四角露出重影。
    static let sourceCornerRadius: CGFloat = 6
    /// 翻转的总角度。**一整圈**，不是半圈。
    ///
    /// 半圈（180°）会让卡片从第一帧起就以镜像示人：书名字反着写，而且持续整整半程 ——
    /// 那不是「一闪而过」，是「一直反着」。整圈则两头都是正的：t = 0 时卡片与被打的
    /// 封面逐像素重合（不跳帧），中途掠过 180° 才有极短一瞬的反字（参考视频里正是
    /// 这一瞬），t = 1 又转正。
    static let turnDegrees: Double = 360
    /// 3D 透视强度，越大越近大远小。
    static let perspective: Double = 0.55
    /// 下拖位移换算成倾倒角度的比例。
    static let dragTilt: Double = 0.03
    /// 出现 / 收回共用的缓动。两处必须同一条曲线，否则「原路翻回」会走样。
    static let animation: Animation = .spring(response: 0.6, dampingFraction: 0.88)
    /// 收回动画的收尾等待。要比曲线沉降久一点，早了会在半空把弹层拆掉。
    /// 多等没有代价：t 归零后卡片本身就是全透明的。
    static let settleMilliseconds: Int = 1000
}

/// 未读书籍的点按弹层（对齐交互参考视频）。
///
/// 刻意不复用 `BookDetailView`（那是 Home 的对话面板，另一种形态）。
/// 动效由单一进度 `t` 驱动，出现 / 收回 / 拖拽共用同一条路径：
/// - 出现（t: 0 → 1）：卡片从被点封面的**原位**起飞 —— 绕 Y 轴翻半圈、带一点 X 轴仰角、
///   放大并平移到屏幕正中；hero 区的虚化封面底随之转正，文字比封面晚一步浮现。
///   背景同步压暗 + 起毛玻璃。
/// - 收回（t: 1 → 0）：下拖跟手（位移 + 轻微倾倒），松手按距离或速度决定
///   「沿来路翻回封面位置」还是回弹；点 ×、点背景同样反向翻回半圈。
struct UnreadBookPeekView: View {
    let book: Book
    /// 被点封面的全局坐标；nil 时退化为从屏幕中央的小卡片翻起。
    let sourceFrame: CGRect?
    let onDismiss: () -> Void
    let onStartReading: () -> Void
    let onListen: () -> Void
    let onRemove: () -> Void

    /// 形态进度：0 = 贴在被点封面上（翻倒、缩小），1 = 屏幕正中的完整卡片。
    @State private var t: Double = 0
    /// 下拖手势的实时位移。
    @State private var dragY: CGFloat = 0
    /// 防止背景 / × / 手势重复触发收回。
    @State private var didDismiss = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cardWidth = size.width - Peek.sideInset * 2
            let cardHeight = size.height * Peek.cardHeightRatio
            let source = sourceFrame ?? fallbackSource(in: size)

            ZStack {
                backdrop

                card(cardWidth: cardWidth, cardHeight: cardHeight, source: source, canvas: size)
                    .gesture(dragGesture(cardHeight: cardHeight))
            }
        }
        .ignoresSafeArea()
        .task {
            // 关键：**不能**在 onAppear 里直接 `withAnimation { t = 1 }`。
            // 弹层是「插入」进来的，那次状态变更会被并进插入的同一帧，
            // 于是 t 一步到位、动画整个消失 —— 表现就是「没有翻转」+
            // 「背景先透明再突然出现毛玻璃」。推到下一轮 runloop，
            // t 的 0 → 1 才是一次独立的、可插值的变更。
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(Peek.animation) { t = 1 }
        }
    }

    /// 没有上报到封面坐标时的退化起点：屏幕中央一张封面大小的卡片。
    private func fallbackSource(in size: CGSize) -> CGRect {
        let width = size.width * 0.3
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - width * 3 / 2) / 2,
            width: width,
            height: width * 3 / 2
        )
    }

    // MARK: - 背景：压暗 + 毛玻璃，点击收回

    /// 压暗与毛玻璃分两层，再整体 `compositingGroup()` 后统一淡入。
    ///
    /// 直接给 `.fill(.regularMaterial)` 挂 `.opacity` 是行不通的：材质由系统合成，
    /// 透明度不是逐帧插值的，结果就是一帧透明、下一帧整块毛玻璃 —— 正是第四条的观感。
    /// 先合成成一层再调透明度，淡入才是连续的。
    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Theme.solidInk.opacity(0.22)
        }
        .compositingGroup()
        .opacity(min(t * 1.6, 1))
        .ignoresSafeArea()
        .onTapGesture { dismiss() }
    }

    // MARK: - 卡片

    private func card(cardWidth: CGFloat, cardHeight: CGFloat, source: CGRect, canvas: CGSize) -> some View {
        ZStack(alignment: .top) {
            // 磨砂面板：底下是材质，透出压暗后的背景；再压一层奶油色把正文对比度拉回来。
            // 单铺一块不透明的 Theme.card 是「纸」，没有玻璃感。
            Rectangle().fill(.regularMaterial)
            Theme.card.opacity(0.55)

            // hero 区的虚化封面底：封面放大到盖满整条 hero，重度模糊后向下渐隐。
            // 缺了这层，卡片顶部就是一块死板的底色 —— 也就是第一条说的「没有背景虚化」。
            heroBackdrop(width: cardWidth, height: cardHeight * Peek.heroRatio)
                .frame(maxHeight: .infinity, alignment: .top)

            detailContent(cardWidth: cardWidth)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(
            RoundedRectangle(cornerRadius: lerpR(Peek.sourceCornerRadius, Radius.xl, t), style: .continuous)
        )
        .shadow(color: Theme.solidInk.opacity(0.28 * t), radius: Peek.cardShadow, y: Spacing.sm * t)
        .scaleEffect(
            x: lerpR(source.width / cardWidth, 1, t),
            y: lerpR(source.height / cardHeight, 1, t),
            anchor: .center
        )
        .rotation3DEffect(
            .degrees(Peek.turnDegrees * (1 - t)),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: Peek.perspective
        )
        // X 轴只跟手、不跟 t：起手若带仰角，卡片就压不严被点的封面，四边会露缝
        .rotation3DEffect(
            .degrees(Double(dragY) * Peek.dragTilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: Peek.perspective
        )
        .offset(
            x: (source.midX - canvas.width / 2) * (1 - t),
            y: (source.midY - canvas.height / 2) * (1 - t) + dragY
        )
        // 起手那一帧卡片是「封面 + 虚化 hero」的合体，和被点的封面并不完全一样，
        // 所以还是要一次极短的交叉淡入：约 1/7 程，0.6s 的曲线下不到 100ms。
        // 再慢就会在半透明状态下看见背后的网格，反而闪。
        .opacity(min(t * 7, 1))
    }

    private func heroBackdrop(width: CGFloat, height: CGFloat) -> some View {
        BookCoverView(book: book)
            .frame(width: width * 1.35)
            .blur(radius: Peek.heroBlur)
            .frame(width: width, height: height, alignment: .center)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: Theme.solidInk, location: 0),
                        .init(color: Theme.solidInk, location: Peek.heroFadeStart),
                        .init(color: Theme.solidInk.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    /// 详情内容：全部左对齐（封面左上、书名、作者、简介），底部居中 Start Reading。
    private func detailContent(cardWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BookCoverView(book: book)
                        .frame(width: cardWidth * Peek.coverWidthRatio)
                        .shadow(color: Theme.solidInk.opacity(0.2), radius: Peek.coverShadow, y: Spacing.xs)
                        .padding(.top, Spacing.lg)

                    Text(book.title)
                        .tText(.sectionTitle)
                        .padding(.top, Spacing.lg)

                    Text(book.author)
                        .tText(.secondary)
                        .padding(.top, Spacing.xs)

                    authorSection
                        .padding(.top, Spacing.xl)

                    startReadingButton
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xl)
                        .padding(.bottom, Spacing.xl)
                }
                .padding(.horizontal, Spacing.xl)
            }
            // 转过了中途那一瞬的镜像再浮现。早了会闪一下**反着的字** ——
            // 起手那几帧卡片还没巴掌大，字挤上去也只会糊成一团。
            .opacity(clamp01((t - 0.55) / 0.3))
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .tIcon(IconRole.emphasis, weight: .medium)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button { dismiss { onListen() } } label: {
                    Label("Listen", systemImage: "headphones")
                }
                .disabled(!book.hasAudio)
                Button(role: .destructive) { dismiss { onRemove() } } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .tIcon(IconRole.control, weight: .bold)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
    }

    /// 「Tell me about the author」一节。
    ///
    /// 标题居中、正文左对齐 —— 参考视频就是这么排的，居中的那句读起来像一个「提问」，
    /// 和产品「与书对话」的定位同源。
    @ViewBuilder
    private var authorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Tell me about the author")
                .tText(.meta)
                .frame(maxWidth: .infinity, alignment: .center)

            // TODO: 文案暂用书籍简介占位。Book / InitialLibrary.json 里都没有作者简介字段，
            // 数据从哪来（补 catalog 字段 / 走 BFF 让模型生成）尚未定，先不挡交互。
            if let text = book.summary, !text.isEmpty {
                Text(text)
                    .tText(.body)
                    .lineSpacing(Spacing.sm)
            }
        }
    }

    private var startReadingButton: some View {
        Button { dismiss { onStartReading() } } label: {
            Text("Start Reading")
                .tText(.button, color: Theme.cream)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(Theme.solidInk, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 手势与收放

    /// 下拖跟手：位移驱动平移 / 轻微倾倒；
    /// 松手按距离（> 卡片高度的 1/5）或速度决定翻回封面原位还是回弹。
    private func dragGesture(cardHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragY = max(0, value.translation.height)
            }
            .onEnded { value in
                let threshold = cardHeight / 5
                if value.translation.height > threshold || value.predictedEndTranslation.height > threshold * 2 {
                    dismiss()
                } else {
                    withAnimation(Peek.animation) { dragY = 0 }
                }
            }
    }

    /// 收回：t 与拖拽位移一起归零（卡片沿来路翻回封面），动画结束后通知父视图移除。
    private func dismiss(completion: (() -> Void)? = nil) {
        guard !didDismiss else { return }
        didDismiss = true
        withAnimation(Peek.animation) {
            t = 0
            dragY = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Peek.settleMilliseconds))
            (completion ?? onDismiss)()
        }
    }
}

// MARK: - 插值工具

private func lerpR(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
