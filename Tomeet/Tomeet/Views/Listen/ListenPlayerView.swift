import SwiftUI

/// 全屏听书播放器：封面 + 进度 + 控制区。风格沿用阅读器主题语义。
struct ListenPlayerView: View {
    let book: Book
    @Environment(AudioPlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var durationMinutes: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()

                BookCoverView(book: book)
                    .frame(width: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 16)

                VStack(spacing: 6) {
                    Text(book.title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                switch player.state {
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message).foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await player.load(book: book) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                default:
                    controls
                }

                Spacer()
            }
            .foregroundStyle(.white)
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
            return "讲书 · 约 \(durationMinutes) 分钟"
        }
        return "讲书"
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
                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    Text("-\(formatTime(max(0, player.duration - player.currentTime)))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            HStack(spacing: 48) {
                Button { player.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15").font(.title)
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                Button { player.skip(by: 15) } label: {
                    Image(systemName: "goforward.15").font(.title)
                }
            }
            .foregroundStyle(.white)

            Button { player.cycleRate() } label: {
                Text(rateLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.15)))
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
