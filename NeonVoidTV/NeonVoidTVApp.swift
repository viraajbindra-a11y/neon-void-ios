import SwiftUI

@main
struct NeonVoidTVApp: App {
    var body: some Scene {
        WindowGroup {
            TVGameView()
                .ignoresSafeArea(.all)
                .preferredColorScheme(.dark)
        }
    }
}
