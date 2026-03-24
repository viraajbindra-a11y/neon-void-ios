import SwiftUI

@main
struct NeonVoidVisionApp: App {
    var body: some Scene {
        // Main game window - flat 2D game in a native visionOS window
        WindowGroup {
            GameWindowView()
        }
        .windowStyle(.plain)
        .defaultSize(width: 1280, height: 800)

        // Immersive ornament: floating ship hologram in your space
        ImmersiveSpace(id: "shipOrnament") {
            ShipOrnamentView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
