import SwiftUI

struct RootView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @State private var selectedTab = 0
    @State private var showNowPlaying = false

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
        // 听书迷你条：safeAreaInset 钉在 TabBar 上方（VStack 会把它压到屏幕最底端、TabBar 之下）
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // DEBUG: 定位 inset 区域
            Color.red.frame(height: 60)
        }
        .animation(.easeInOut(duration: 0.25), value: audioPlayer.isNowPlayingBarVisible)
        .fullScreenCover(isPresented: $showNowPlaying) {
            if let book = audioPlayer.currentBook {
                ListenPlayerView(book: book)
            }
        }
        .tint(Theme.accent)
        // Theme 色板只有浅色一套，锁定浅色模式，避免系统深色翻转键盘/弹窗等系统表面。
        .preferredColorScheme(.light)
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
