import SwiftUI

struct SearchView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Search",
                systemImage: "magnifyingglass",
                description: Text("搜索将在后续里程碑实现")
            )
            .navigationTitle("Search")
            .searchable(text: $searchText)
        }
    }
}