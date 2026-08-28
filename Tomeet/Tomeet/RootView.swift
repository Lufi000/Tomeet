import SwiftUI

struct RootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(1)
            AIAssistantView(onBack: { selectedTab = 0 })
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(2)
        }
        .tint(Theme.accent)
    }
}
