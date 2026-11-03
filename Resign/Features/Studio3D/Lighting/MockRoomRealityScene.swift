import RealityKit
import Observation
import UIKit

/// Fixed ceiling projection of MockRoom.usdz for the lighting placement screen.
/// With `topDown: true` the materials are unlit, so placement colors never depend on the lighting simulation.
/// The 3D lighting preview uses `RoomSceneController` instead.
@MainActor
@Observable
final class MockRoomRealityScene {
    let root = Entity()
    let camera = Entity()
    let topDown: Bool
    var loadFailed = false
    var yaw: Float = -0.73
    var pitch: Float = 0.55
    var distance: Float = 12
    private(set) var room: Entity?

    init(topDown: Bool) {
        self.topDown = topDown
    }

    func load() async throws {
        guard room == nil else { return }
        guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let loaded = try await Entity(contentsOf: url)
        try Task.checkCancellation()
        configure(loaded)
        root.addChild(loaded)
        room = loaded

        if topDown {
            var orthographic = OrthographicCameraComponent()
            orthographic.scale = 4.2
            orthographic.scaleDirection = .vertical
            orthographic.near = 0.1
            orthographic.far = 30
            camera.components.set(orthographic)
            camera.look(at: .zero, from: [0, 10, 0], upVector: [0, 0, -1], relativeTo: nil)
        } else {
            var perspective = PerspectiveCameraComponent()
            perspective.fieldOfViewInDegrees = 40
            camera.components.set(perspective)
            updateCamera()
        }
        root.addChild(camera)
    }

    func updateCamera() {
        let target: SIMD3<Float> = [0, 0.7, 0]
        let offset = SIMD3<Float>(
            sin(yaw) * cos(pitch),
            sin(pitch),
            cos(yaw) * cos(pitch)
        ) * distance
        camera.look(at: target, from: target + offset, relativeTo: nil)
    }

    /// Kept so older call sites still compile. The top-down scene has no lights to update.
    func apply(_ settings: LightingSimulationSettings) {}

    private func configure(_ entity: Entity) {
        let name = entity.name
        if name == "Ceiling" || (!topDown && (name == "Wall_West" || name.hasPrefix("Wall_South") || name == "Door")) {
            entity.isEnabled = false
        }

        if var model = entity.components[ModelComponent.self] {
            if topDown {
                model.materials = model.materials.map { material in
                    if let pbr = material as? PhysicallyBasedMaterial {
                        var unlit = UnlitMaterial()
                        unlit.color = .init(tint: pbr.baseColor.tint, texture: pbr.baseColor.texture)
                        return unlit
                    }
                    return material
                }
            }
            entity.components.set(model)
        }
        for child in entity.children {
            configure(child)
        }
    }
}
