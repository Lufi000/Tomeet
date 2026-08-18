import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
        }
        .tint(.blue)
    }
}
