import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            Text("Library")
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}