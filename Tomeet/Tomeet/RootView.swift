import SwiftUI

struct RootView: View {
    @State private var selectedTab = 0

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
        .tint(Theme.accent)
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
