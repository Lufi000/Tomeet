import SwiftUI

/// 开屏：品牌页淡入展示「阅读没有门槛」宣言，随后交叉淡出进入主界面。
/// 每次冷启动展示约 2 秒，点按可跳过。
struct SplashView<Content: View>: View {
    @ViewBuilder let content: Content

    /// 刺猬插画是否已入场
    @State private var imageAppeared = false
    /// 文案是否已入场（比插画稍晚，形成先后层次）
    @State private var textAppeared = false
    /// 主界面是否已经就绪并可见（开屏结束时淡入）
    @State private var isContentReady = false
    /// 开屏整体透明度，结束时淡出
    @State private var splashOpacity = 1.0

    private let autoDismissDelay: TimeInterval = 2.2
    private let crossfadeDuration: TimeInterval = 0.6

    var body: some View {
        ZStack {
            content
                .opacity(isContentReady ? 1 : 0)

            splash
                .opacity(splashOpacity)
                .allowsHitTesting(splashOpacity > 0.5)
                .onTapGesture { dismiss() }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                imageAppeared = true
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.55)) {
                textAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDelay) {
                dismiss()
            }
        }
    }

    /// 开屏画面：水彩刺猬 + Tomeet 字标 + 品牌宣言
    private var splash: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 32) {
                Image("SplashHedgehog")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 320)
                    .scaleEffect(imageAppeared ? 1 : 0.92)
                    .opacity(imageAppeared ? 1 : 0)

                VStack(spacing: 16) {
                    Text("Tomeet")
                        .font(.splendid(.largeTitle, weight: .bold))
                        .splendidTracking(.largeTitle)
                        .foregroundStyle(Theme.ink)

                    VStack(spacing: 8) {
                        Text("Reading is for everyone")
                            .font(.splendid(.title3))
                            .splendidTracking(.title3)
                            .foregroundStyle(Theme.ink)
                        Text("Every book's mind is waiting to talk with you")
                            .font(.splendid(.callout))
                            .splendidTracking(.callout)
                            .foregroundStyle(Theme.inkSecondary)
                        // 电影《刺猬的优雅》的法文原名，作为品牌精神的小字落款
                        Text("L'élégance du hérisson")
                            .font(.splendid(.caption2))
                            .tracking(0)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared ? 0 : 12)
            }
        }
    }

    /// 交叉淡出开屏、同时淡入主界面
    private func dismiss() {
        guard splashOpacity > 0 else { return }
        withAnimation(.easeInOut(duration: crossfadeDuration)) {
            isContentReady = true
            splashOpacity = 0
        }
    }
}
