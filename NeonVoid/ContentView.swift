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
        #if targetEnvironment(macCatalyst)
        .onAppear {
            // Fullscreen window on Mac
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.titlebar?.titleVisibility = .hidden
                windowScene.titlebar?.toolbar = nil
            }
        }
        #endif
    }
}
