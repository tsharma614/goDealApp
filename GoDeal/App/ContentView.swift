import SwiftUI

// ContentView is the root view, routing to MainMenuView.
// Kept minimal — navigation logic lives in MainMenuView.
struct ContentView: View {
    var body: some View {
        MainMenuView()
    }
}

#Preview {
    ContentView()
}
