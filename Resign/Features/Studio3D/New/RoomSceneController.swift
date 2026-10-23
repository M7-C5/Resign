import RealityKit
import Observation
import UIKit
import simd

/// Loads MockRoom.usdz, owns the orbit camera and the lighting rig.
@MainActor
@Observable
final class RoomSceneController {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var loadState: LoadState = .idle

    let root = Entity()
    let rig = RoomLightingRig()
    private let camera = PerspectiveCamera()
    private var room: Entity?

    // Orbit state. Plain storage: changing it must not trigger SwiftUI updates.
    @ObservationIgnored var yaw: Float = -0.73
    @ObservationIgnored var pitch: Float = 0.55
    @ObservationIgnored var distance: Float = 12

    init() {
        root.name = "MockRoomRoot"
        camera.camera.fieldOfViewInDegrees = 40
        camera.camera.near = 0.1
        camera.camera.far = 60
        root.addChild(rig.root)
        root.addChild(camera)
        updateCamera()
    }

    /// Puts the scene into an ARView (non-AR) and creates the lights.
    func install(in view: ARView) {
        rig.buildIfNeeded()
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(root)
        view.scene.addAnchor(anchor)
    }

    func load() async {
        guard room == nil, loadState != .loading else { return }
        loadState = .loading
        do {
            guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let loaded = try await Entity(contentsOf: url)
            try Task.checkCancellation()
            prepare(loaded)
            root.addChild(loaded)
            room = loaded
            let opening = findWindow(in: loaded)
            let lamps = findFixtures(in: loaded)
            rig.configure(opening: opening, fixturePositions: lamps)
            #if DEBUG
            let windowText = opening.map { "center=\($0.center) size=\($0.width)x\($0.height)" } ?? "not found, using default"
            print("[MockRoom] window: \(windowText) | lamps found: \(lamps.count) \(lamps)")
            #endif
            loadState = .loaded
            #if DEBUG
            RoomDebug.dump(loaded)
            #endif
        } catch is CancellationError {
            loadState = .idle
        } catch {
            loadState = .failed
        }
    }

    // MARK: - Camera

    func setOrbit(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = min(1.35, max(0.15, pitch))
        updateCamera()
    }

    func setDistance(_ value: Float) {
        distance = min(20, max(5, value))
        updateCamera()
    }

    private func updateCamera() {
        let target: SIMD3<Float> = [0, 0.7, 0]
        let offset = SIMD3<Float>(
            sin(yaw) * cos(pitch),
            sin(pitch),
            cos(yaw) * cos(pitch)
        ) * distance
        camera.look(at: target, from: target + offset, relativeTo: nil)
    }

    // MARK: - Model preparation

    /// Cutaway walls, and decide which meshes cast shadows.
    private func prepare(_ entity: Entity) {
        let name = entity.name
        if name == "Ceiling" || name == "Wall_West" || name.hasPrefix("Wall_South") || name == "Door" {
            entity.isEnabled = false
        }
        if entity.components.has(ModelComponent.self) {
            entity.components.set(DynamicLightShadowComponent(castsShadow: castsShadow(named: name)))
        }
        for child in entity.children {
            prepare(child)
        }
    }

    // MARK: - Finding the window and lamps in the model

    private func modelEntities(in entity: Entity) -> [Entity] {
        var result: [Entity] = []
        if entity.components.has(ModelComponent.self) { result.append(entity) }
        for child in entity.children { result += modelEntities(in: child) }
        return result
    }

    private func union(_ boxes: [BoundingBox]) -> BoundingBox? {
        guard var result = boxes.first else { return nil }
        for box in boxes.dropFirst() {
            result = BoundingBox(min: simd_min(result.min, box.min), max: simd_max(result.max, box.max))
        }
        return result
    }

    /// Uses the bounds of the mesh(es) named "glass" on the east wall as the window opening.
    private func findWindow(in model: Entity) -> WindowOpening? {
        let glass = modelEntities(in: model).filter { $0.name.lowercased().contains("glass") }
        guard let box = union(glass.map { $0.visualBounds(relativeTo: nil) }), box.center.x > 1 else {
            return nil
        }
        return WindowOpening(center: box.center, width: box.extents.z, height: box.extents.y)
    }

    /// Looks for ceiling lamp meshes by name and returns a spot position just below each one.
    private func findFixtures(in model: Entity) -> [SIMD3<Float>] {
        let keywords = ["light", "lamp", "fixture", "bulb", "pendant"]
        var boxes: [BoundingBox] = []
        for entity in modelEntities(in: model) {
            let name = entity.name.lowercased()
            guard !name.contains("glass"), keywords.contains(where: { name.contains($0) }) else { continue }
            let box = entity.visualBounds(relativeTo: nil)
            if box.center.y > 1.5 { boxes.append(box) }
        }

        var clusters: [BoundingBox] = []
        for box in boxes {
            if let index = clusters.firstIndex(where: { simd_distance($0.center, box.center) < 0.35 }) {
                clusters[index] = union([clusters[index], box]) ?? clusters[index]
            } else {
                clusters.append(box)
            }
        }
        return clusters.prefix(6).map {
            SIMD3<Float>($0.center.x, $0.min.y - 0.03, $0.center.z)
        }
    }

    /// Glass and anything that looks like a lamp must not cast shadows,
    /// otherwise a fixture mesh wrapped around a light source blocks all of its light.
    private func castsShadow(named name: String) -> Bool {
        let lowered = name.lowercased()
        let nonCasters = ["glass", "light", "lamp", "fixture", "bulb"]
        return !nonCasters.contains { lowered.contains($0) }
    }
}

#if DEBUG
/// Prints the model hierarchy to the Xcode console so real positions and materials can be checked.
@MainActor
enum RoomDebug {
    static func dump(_ entity: Entity, depth: Int = 0) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let materials = entity.components[ModelComponent.self]?.materials
            .map { String(describing: type(of: $0)) } ?? []
        let indent = String(repeating: "  ", count: depth)
        print("[MockRoom] \(indent)\(entity.name) center=\(bounds.center) size=\(bounds.extents) materials=\(materials)")
        for child in entity.children {
            dump(child, depth: depth + 1)
        }
    }
}
#endif
