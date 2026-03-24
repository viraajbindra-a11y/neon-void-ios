import SwiftUI
import RealityKit

struct ShipOrnamentView: View {
    @State private var angle: Float = 0

    var body: some View {
        RealityView { content in
            // Create a floating neon ship entity
            let ship = createShipEntity()
            ship.position = [0, 1.5, -1.5] // Float in front of user
            content.add(ship)

            // Add ambient neon light
            let light = Entity()
            var pointLight = PointLightComponent(
                color: .cyan,
                intensity: 500,
                attenuationRadius: 2.0
            )
            light.components.set(pointLight)
            light.position = [0, 1.8, -1.3]
            content.add(light)

        } update: { content in
            // Rotate ship slowly
            if let ship = content.entities.first {
                angle += 0.005
                ship.transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
                // Gentle bob
                let bob = sin(angle * 3) * 0.03
                ship.position.y = 1.5 + bob
            }
        }
    }

    func createShipEntity() -> ModelEntity {
        // Main fuselage - elongated box
        let fuselage = MeshResource.generateBox(
            width: 0.15, height: 0.04, depth: 0.3,
            cornerRadius: 0.01
        )
        var fuselageMat = SimpleMaterial()
        fuselageMat.color = .init(tint: UIColor(red: 1.0, green: 0.0, blue: 0.33, alpha: 1.0))
        fuselageMat.roughness = 0.3
        fuselageMat.metallic = 0.8

        let shipEntity = ModelEntity(mesh: fuselage, materials: [fuselageMat])

        // Left wing
        let wing = MeshResource.generateBox(
            width: 0.2, height: 0.01, depth: 0.12,
            cornerRadius: 0.005
        )
        var wingMat = SimpleMaterial()
        wingMat.color = .init(tint: UIColor(red: 0.8, green: 0.0, blue: 0.25, alpha: 1.0))
        wingMat.roughness = 0.4
        wingMat.metallic = 0.7

        let leftWing = ModelEntity(mesh: wing, materials: [wingMat])
        leftWing.position = [-0.12, 0, -0.05]
        leftWing.transform.rotation = simd_quatf(angle: -0.15, axis: [0, 0, 1])
        shipEntity.addChild(leftWing)

        let rightWing = ModelEntity(mesh: wing, materials: [wingMat])
        rightWing.position = [0.12, 0, -0.05]
        rightWing.transform.rotation = simd_quatf(angle: 0.15, axis: [0, 0, 1])
        shipEntity.addChild(rightWing)

        // Cockpit - glowing cyan sphere
        let cockpit = MeshResource.generateSphere(radius: 0.025)
        var cockpitMat = SimpleMaterial()
        cockpitMat.color = .init(tint: UIColor(red: 0.0, green: 1.0, blue: 0.8, alpha: 0.9))
        cockpitMat.roughness = 0.1
        cockpitMat.metallic = 0.0

        let cockpitEntity = ModelEntity(mesh: cockpit, materials: [cockpitMat])
        cockpitEntity.position = [0, 0.025, 0.08]
        shipEntity.addChild(cockpitEntity)

        // Engine glow - two small cyan spheres at back
        let engineGlow = MeshResource.generateSphere(radius: 0.015)
        var engineMat = SimpleMaterial()
        engineMat.color = .init(tint: UIColor(red: 0.0, green: 1.0, blue: 0.8, alpha: 0.8))
        engineMat.roughness = 0.0
        engineMat.metallic = 0.0

        let leftEngine = ModelEntity(mesh: engineGlow, materials: [engineMat])
        leftEngine.position = [-0.04, 0, -0.15]
        shipEntity.addChild(leftEngine)

        let rightEngine = ModelEntity(mesh: engineGlow, materials: [engineMat])
        rightEngine.position = [0.04, 0, -0.15]
        shipEntity.addChild(rightEngine)

        // Scale up
        shipEntity.scale = [2.0, 2.0, 2.0]

        return shipEntity
    }
}
