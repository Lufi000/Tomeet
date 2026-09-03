import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var showNowPlaying = false
    /// TabBar 胶囊顶边距底部的距离（实测）；读到前按常见胶囊高度兜底
    @State private var tabBarTopInset: CGFloat = 60

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { tabLabel("Home", selectedImage: "TabHome", unselectedImage: "TabHomeUnselected", tag: 0) }
                .tag(0)
            LibraryView()
                .tabItem { tabLabel("Library", selectedImage: "TabLibrary", unselectedImage: "TabLibraryUnselected", tag: 1) }
                .tag(1)
            AIAssistantView(onBack: { selectedTab = 0 })
                .tabItem { tabLabel("AI", selectedImage: "TabAI", unselectedImage: "TabAIUnselected", tag: 2) }
                .tag(2)
        }
        // 听书迷你条：悬浮在 TabBar 上方。iOS 26 悬浮 TabBar 不吃 safeAreaInset
        // （inset 内容会落到胶囊后面被盖住），只能 overlay + 实测 TabBar 帧定位。
        .overlay(alignment: .bottom) {
            // AI 聊天 tab 不显示迷你条，避免遮挡对话
            if audioPlayer.isNowPlayingBarVisible && selectedTab != 2 {
                NowPlayingBar {
                    showNowPlaying = true
                }
                .padding(.bottom, tabBarTopInset + 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // 零高占位：底边与 overlay 底对齐，作为 TabBar 帧的测量坐标系
            TabBarTopInsetReader(inset: $tabBarTopInset)
                .frame(height: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: audioPlayer.isNowPlayingBarVisible)
        // 悬浮胶囊不占 safe area，把实测留白注入给各 tab 的滚动容器
        .environment(\.tabContentBottomInset, tabContentBottomInset)
        .fullScreenCover(isPresented: $showNowPlaying) {
            if let book = audioPlayer.currentBook {
                ListenPlayerView(book: book)
            }
        }
        .tint(Theme.accent)
        // 临时调试：-DebugTogglePlayback 启动参数下自动播放并周期切换播放/暂停，复现迷你条图标闪烁
        .task {
            guard CommandLine.arguments.contains("-DebugTogglePlayback") else { return }
            let books = (try? modelContext.fetch(FetchDescriptor<Book>())) ?? []
            guard let book = books.first(where: { BookSourceResolver.audioURL(for: $0) != nil }) else { return }
            await audioPlayer.load(book: book)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                audioPlayer.togglePlayPause()
            }
        }
        // Theme 色板只有浅色一套，锁定浅色模式，避免系统深色翻转键盘/弹窗等系统表面。
        .preferredColorScheme(.light)
    }

    /// Home/Library 滚动容器的底部留白：胶囊高度；播放条出现时再加其高度(56)与间距(8)。
    private var tabContentBottomInset: CGFloat {
        var inset = tabBarTopInset
        if audioPlayer.isNowPlayingBarVisible && selectedTab != 2 {
            inset += 64
        }
        return inset
    }

    /// 水彩插画 Tab 图标：选中彩色、未选中灰调，均保持原色渲染。
    /// 选中态变化时改 .id 强制重建 Label，否则 UIKit 可能不刷新 tabItem 图片。
    private func tabLabel(_ title: String, selectedImage: String, unselectedImage: String, tag: Int) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(selectedTab == tag ? selectedImage : unselectedImage)
                .renderingMode(.original)
        }
        .id("\(title)-\(selectedTab == tag)")
    }
}
