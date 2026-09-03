import SwiftUI

/// 迷你播放条：钉在 TabBar 上方，显示正在听的书 + 进度 + 播放/暂停。
/// 点卡片主体展开全屏播放器（数据全部来自 AudioPlayerService，与所在页面无关）。
struct NowPlayingBar: View {
    @Environment(AudioPlayerService.self) private var player
    let onExpand: () -> Void

    var body: some View {
        if player.isNowPlayingBarVisible {
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            if let book = player.currentBook {
                BookCoverView(book: book)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .splendidContentFont(.subheadline, weight: .semibold, text: book.title)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(narrationLabel(for: book))
                        .splendidContentFont(.caption2, text: narrationLabel(for: book))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                }
            } else {
                // 加载中：书还没挂上，先给转圈占位
                ProgressView()
                    .tint(Theme.accent)
                    .controlSize(.small)
                Text(Self.loadingLabel)
                    .splendidContentFont(.subheadline, text: Self.loadingLabel)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(player.currentBook == nil)

            // 关闭：停止播放并收起迷你条
            Button {
                player.unload()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(width: 28, height: 28)
                    .background(Theme.inkTertiary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.card)
                // 底部细进度条：scaleEffect 按 leading 锚点伸缩，省去 GeometryReader
                Theme.accent
                    .frame(height: 3)
                    .scaleEffect(x: progressFraction, anchor: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 加载中没有可展开的书，忽略点击
            if player.currentBook != nil {
                onExpand()
            }
        }
        .padding(.horizontal, 12)
    }

    /// 本地化后的副标题/占位文案。`splendidContentFont(text:)` 靠内容判断 CJK，
    /// 必须传本地化后的实际文本，不能传英文 key。
    private static let loadingLabel = String(localized: "Loading…")

    private func narrationLabel(for book: Book) -> String {
        String(localized: "Narration · \(book.author)")
    }

    private var progressFraction: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }
}
