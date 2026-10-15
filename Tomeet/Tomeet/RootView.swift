import SwiftUI

struct RootView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @State private var showLibrary = false
    @State private var showNowPlaying = false
    @State private var bookOpening = BookOpening()

    var body: some View {
        // **没有底部标签栏**（Paper 的交互）：App 只有首页一屏，
        // 书架从顶部 ☰ 从底部升起。
        HomeView(onOpenLibrary: { showLibrary = true })
        // 打开一本书的动效要盖住整个界面，所以呈现层挂在最外层。
        // Home / Library 通过这个环境值发起打开。
        .environment(bookOpening)
        // 听书迷你条：safeAreaInset 钉在底部
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NowPlayingBar(onExpand: { showNowPlaying = true })
        }
        // 书架。`bookOpening` 要显式再注入一次 —— sheet 的内容是新的呈现树。
        .sheet(isPresented: $showLibrary) {
            LibraryView()
                .environment(bookOpening)
        }
        .animation(.easeInOut(duration: 0.25), value: audioPlayer.isNowPlayingBarVisible)
        .fullScreenCover(isPresented: $showNowPlaying) {
            if let book = audioPlayer.currentBook {
                ListenPlayerView(book: book)
            }
        }
        .onAppear {
            #if DEBUG
            // 录屏验证时直接拉起书架 —— 那些钩子都长在 LibraryView 上，
            // 不先把它打开，钩子根本不会跑。
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--ui-snapshot-peek")
                || args.contains("--ui-snapshot-open")
                || args.contains("--ui-snapshot-library")
                || args.contains("--ui-snapshot-search")
                || args.contains("--ui-snapshot-import") {
                showLibrary = true
            }
            #endif
        }
        .tint(Theme.accent)
        // Theme 色板只有浅色一套，锁定浅色模式，避免系统深色翻转键盘/弹窗等系统表面。
        .preferredColorScheme(.light)
        .overlay {
            if let request = bookOpening.request {
                BookOpenTransition(request: request) { bookOpening.finish() }
            }
        }
    }

}
