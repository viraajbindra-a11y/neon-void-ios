import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { geo in
            GameWebView(safeAreaInsets: geo.safeAreaInsets)
                .ignoresSafeArea(.all)
        }
        .background(Color.black)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
