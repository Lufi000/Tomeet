import SwiftData
import SwiftUI

/// 全屏听书播放器：封面 + 进度 + 控制区。配色沿用首页主题（Theme 色板）。
/// 听书时长统计在 AudioPlayerService 里按播放状态计，这里只管进度写回。
struct ListenPlayerView: View {
    let book: Book
    @Environment(AudioPlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var durationMinutes: Int?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.splendid(.title2)).splendidTracking(.title2)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .padding()

                BookCoverView(book: book)
                    .frame(width: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 4)

                VStack(spacing: 6) {
                    Text(book.title)
                        .splendidContentFont(.title3, weight: .semibold, text: book.title)
                    Text(subtitle)
                        .splendidContentFont(.subheadline, text: subtitle)
                        .foregroundStyle(Theme.inkSecondary)
                }

                switch player.state {
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message)
                            .font(.splendid(.body))
                            .foregroundStyle(Theme.inkSecondary)
                        Button("Retry") {
                            Task { await player.load(book: book) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                default:
                    controls
                }

                Spacer()
            }
            .foregroundStyle(Theme.ink)
        }
        .task {
            await player.load(book: book)
        }
        .task {
            if let catalog = try? InitialLibraryLoader.load(),
               let catalogID = book.catalogID {
                durationMinutes = InitialLibraryLoader.book(for: catalogID, in: catalog)?.audio?.durationMinutes
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                player.saveProgress()
            }
        }
        .onDisappear {
            player.saveProgress()
        }
    }

    private var subtitle: String {
        if let durationMinutes {
            return String(localized: "Narration · ~\(durationMinutes) min")
        }
        return String(localized: "Narration")
    }

    private var controls: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .tint(Theme.accent)
                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    Text("-\(formatTime(max(0, player.duration - player.currentTime)))")
                }
                .font(.splendid(.caption).monospacedDigit())
                .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 32)

            HStack(spacing: 48) {
                Button { player.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15").font(.title)
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Theme.accent)
                }
                Button { player.skip(by: 15) } label: {
                    Image(systemName: "goforward.15").font(.title)
                }
            }
            .foregroundStyle(Theme.ink)

            Button { player.cycleRate() } label: {
                Text(rateLabel)
                    .font(.splendid(.subheadline, weight: .semibold)).splendidTracking(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.inkTertiary.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private var rateLabel: String {
        // %g：1.25→"1.25x"、2.0→"2x"、0.75→"0.75x"；1.0 特判为 "1.0x"（与预设标签一致）
        player.rate == 1.0 ? "1.0x" : String(format: "%gx", player.rate)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
