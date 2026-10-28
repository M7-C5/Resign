import RealityKit
import Observation
import UIKit
import simd

/// Loads the selected scan, owns the orbit camera and the lighting rig.
@MainActor
@Observable
final class RoomSceneController {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var loadState: LoadState = .idle
    private(set) var resolvedWindowAzimuths: [Double]?

    let root = Entity()
    let rig: RoomLightingRig
    private let camera = PerspectiveCamera()
    private var room: Entity?
    private let layout: RoomSimulationLayout?
    @ObservationIgnored private var cameraTarget: SIMD3<Float> = [0, 0.7, 0]
    @ObservationIgnored private var roomExtent: Float = 5

    // Orbit state. Plain storage: changing it must not trigger SwiftUI updates.
    @ObservationIgnored var yaw: Float = -0.73
    @ObservationIgnored var pitch: Float = 0.55
    @ObservationIgnored var distance: Float = 12

    init(fixtures: [RoomLightingFixture]? = nil, layout: RoomSimulationLayout? = nil) {
        self.layout = layout
        rig = RoomLightingRig(fixtures: fixtures)
        root.name = layout == nil ? "MockRoomRoot" : "ScannedRoomRoot"
        // The default non-AR environment otherwise washes out the window lights,
        // even when the view's environment intensity exponent is reduced.
        root.components.set(EnvironmentLightingConfigurationComponent(environmentLightingWeight: 0))
        root.components.set(ImageBasedLightComponent(source: .none))
        root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        camera.camera.fieldOfViewInDegrees = 40
        camera.camera.near = 0.1
        camera.camera.far = 60
        root.addChild(rig.root)
        root.addChild(camera)
        if let layout {
            pitch = 0.9
            roomExtent = max(layout.width, layout.length)
        }
        updateCamera()
    }

    func setLightingFixtures(_ fixtures: [RoomLightingFixture]?) {
        rig.setFixtures(fixtures)
    }

    /// Puts the scene into an ARView (non-AR) and creates the lights.
    func install(in view: ARView) {
        rig.buildIfNeeded()
        if let layout {
            rig.configure(openings: layout.windows, roomCenter: [0, layout.height * 0.65, 0])
        }
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(root)
        view.scene.addAnchor(anchor)
    }

    func load() async {
        guard room == nil, loadState != .loading else { return }
        loadState = .loading
        do {
            if let layout {
                try await loadScannedLayout(layout)
                loadState = .loaded
                return
            }
            guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let loaded = try await Entity(contentsOf: url)
            try Task.checkCancellation()
            prepare(loaded)
            root.addChild(loaded)
            room = loaded
            let opening = findWindow(in: loaded)
            rig.configure(opening: opening)
            #if DEBUG
            let windowText = opening.map { "center=\($0.center) size=\($0.width)x\($0.height)" } ?? "not found, using default"
            print("[MockRoom] window: \(windowText) | layout fixtures: \(rig.fixtureCount)")
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

    private func loadScannedLayout(_ input: RoomSimulationLayout) async throws {
        var source = input
        let normalizedRoom = Entity()
        normalizedRoom.name = "ScannedLayout_\(source.id)"
        let captureSpace = Entity()
        captureSpace.name = "CaptureSpace"
        normalizedRoom.addChild(captureSpace)

        var shell: Entity?
        if let url = source.modelURL, FileManager.default.fileExists(atPath: url.path) {
            shell = try? await Entity(contentsOf: url)
        }
        try Task.checkCancellation()
        if let shell {
            shell.findEntity(named: "Object_grp")?.isEnabled = false
            prepareScanned(shell)
            if source.scanPlan == nil {
                let bounds = shell.visualBounds(relativeTo: nil)
                source.center = [bounds.center.x, bounds.center.z]
            }
            if source.scanPlan?.floorLevel == nil,
               let floor = shell.findEntity(named: "Floor_grp") {
                source.floorLevel = floor.visualBounds(relativeTo: nil).center.y
            }
            // Some native parametric exports represent walls as solid boxes, including
            // behind the window pane. Saved wall panels provide actual aperture holes.
            if source.wallSegments.isEmpty {
                source.inferredWallSegments = nativeWallSegments(in: shell, source: source)
            }
            if !source.wallSegments.isEmpty {
                hideNativeWallMeshes(shell)
                normalizedRoom.addChild(makeScannedShell(source, includeFloor: false))
            }
            captureSpace.addChild(shell)
        } else {
            normalizedRoom.addChild(makeScannedShell(source))
        }

        if shell?.findEntity(named: "Furniture") == nil {
            for item in source.furnishings {
                let furniture = Furniture(
                    id: item.id, name: item.name, category: item.category,
                    positionX: item.position.x, positionY: item.position.y, positionZ: item.position.z,
                    rotationYaw: item.yaw, length: item.dimensions.z,
                    width: item.dimensions.x, height: item.dimensions.y, usdzURL: item.modelURL
                )
                let entity = FurnitureEntityFactory.createEntity(for: furniture)
                prepareScanned(entity)
                captureSpace.addChild(entity)
            }
        }
        let inverseYaw = simd_quatf(angle: -source.yaw, axis: [0, 1, 0])
        captureSpace.orientation = inverseYaw
        captureSpace.position = inverseYaw.act([-source.center.x, -source.floorLevel, -source.center.y])

        try Task.checkCancellation()
        root.addChild(normalizedRoom)
        room = normalizedRoom
        rig.configure(openings: source.windows, roomCenter: [0, source.height * 0.65, 0])
        resolvedWindowAzimuths = source.windowAzimuths
        let bounds = normalizedRoom.visualBounds(relativeTo: root)
        roomExtent = max(2, max(bounds.extents.x, max(bounds.extents.z, source.height)))
        cameraTarget = [bounds.center.x, source.height * 0.35, bounds.center.z]
        distance = roomExtent * 1.9
        camera.camera.far = max(60, distance * 5)
        updateCamera()
    }

    private func prepareScanned(_ entity: Entity, windowAncestor: Bool = false) {
        let name = entity.name.lowercased()
        let isWindow = windowAncestor || name.contains("window") || name.contains("glass")
        if name.contains("ceiling") { entity.isEnabled = false }
        if var model = entity.components[ModelComponent.self] {
            if isWindow {
                model.materials = [SimpleMaterial(color: UIColor(white: 0.85, alpha: 0.1), roughness: 0.1, isMetallic: false)]
            } else if name.contains("wall") {
                model.materials = [SimpleMaterial(color: UIColor(white: 0.92, alpha: 1), roughness: 0.85, isMetallic: false)]
            } else if name.contains("floor") {
                model.materials = [SimpleMaterial(color: UIColor(red: 0.68, green: 0.53, blue: 0.38, alpha: 1), roughness: 0.6, isMetallic: false)]
            }
            entity.components.set(model)
            entity.components.set(DynamicLightShadowComponent(castsShadow: !isWindow && castsShadow(named: name)))
        }
        for child in entity.children { prepareScanned(child, windowAncestor: isWindow) }
    }

    private func hideNativeWallMeshes(_ entity: Entity) {
        if entity.components.has(ModelComponent.self), entity.name.lowercased().contains("wall") {
            entity.isEnabled = false
        }
        for child in entity.children { hideNativeWallMeshes(child) }
    }

    /// Older saved rooms can recover wall spans from the exported native model.
    private func nativeWallSegments(in shell: Entity, source: RoomSimulationLayout) -> [RoomPlanSnapshot.WallSegment] {
        modelEntities(in: shell).filter { $0.name.lowercased().contains("wall") }.compactMap { entity in
            let bounds = entity.visualBounds(relativeTo: entity)
            guard max(bounds.extents.x, bounds.extents.z) > 0.01 else { return nil }
            var start = bounds.center
            var end = bounds.center
            if bounds.extents.x >= bounds.extents.z {
                start.x = bounds.min.x
                end.x = bounds.max.x
            } else {
                start.z = bounds.min.z
                end.z = bounds.max.z
            }
            let matrix = entity.transformMatrix(relativeTo: nil)
            let a = matrix * SIMD4<Float>(start.x, start.y, start.z, 1)
            let b = matrix * SIMD4<Float>(end.x, end.y, end.z, 1)
            let localA = source.localPosition([a.x, a.y, a.z])
            let localB = source.localPosition([b.x, b.y, b.z])
            return .init(startX: localA.x, startZ: localA.z, endX: localB.x, endZ: localB.z)
        }
    }

    /// Reconstructs the saved walls and aperture holes if the exported asset is unavailable.
    private func makeScannedShell(_ source: RoomSimulationLayout, includeFloor: Bool = true) -> Entity {
        let shell = Entity()
        shell.name = includeFloor ? "ReconstructedScanShell" : "ScannedApertureWalls"
        if includeFloor {
            let floorMaterial = SimpleMaterial(color: UIColor(red: 0.68, green: 0.53, blue: 0.38, alpha: 1), roughness: 0.6, isMetallic: false)
            let floor = ModelEntity(mesh: .generateBox(size: [source.width, 0.08, source.length]), materials: [floorMaterial])
            floor.name = "ScannedFloor"
            floor.position.y = -0.04
            shell.addChild(floor)
        }
        let fallbackWalls: [RoomPlanSnapshot.WallSegment] = [
            .init(startX: -source.width / 2, startZ: -source.length / 2, endX: source.width / 2, endZ: -source.length / 2),
            .init(startX: source.width / 2, startZ: -source.length / 2, endX: source.width / 2, endZ: source.length / 2),
            .init(startX: source.width / 2, startZ: source.length / 2, endX: -source.width / 2, endZ: source.length / 2),
            .init(startX: -source.width / 2, startZ: source.length / 2, endX: -source.width / 2, endZ: -source.length / 2)
        ]
        let capturedWalls = source.wallSegments
        let walls = capturedWalls.isEmpty ? fallbackWalls : capturedWalls
        for (index, wall) in walls.enumerated() {
            addWall(wall, index: index, source: source, to: shell)
        }
        return shell
    }

    private func addWall(_ wall: RoomPlanSnapshot.WallSegment, index: Int, source: RoomSimulationLayout, to shell: Entity) {
        let start = SIMD2<Float>(wall.startX, wall.startZ)
        let delta = SIMD2<Float>(wall.endX - wall.startX, wall.endZ - wall.startZ)
        let length = simd_length(delta)
        guard length > 0.02 else { return }
        let direction = delta / length
        // Partition the wall into solid panels around every saved opening.
        var holes: [(left: Float, right: Float, bottom: Float, top: Float)] = []
        for aperture in source.apertures {
            let p = source.localPosition(aperture.position)
            let offset = SIMD2<Float>(p.x, p.z) - start
            let along = simd_dot(offset, direction)
            let perpendicular = abs(offset.x * direction.y - offset.y * direction.x)
            if perpendicular < 0.25, along >= -0.1, along <= length + 0.1 {
                let left = min(length, max(0, along - aperture.width / 2))
                let right = min(length, max(0, along + aperture.width / 2))
                let bottom = min(source.height, max(0, p.y - aperture.height / 2))
                let top = min(source.height, max(0, p.y + aperture.height / 2))
                if right > left, top > bottom { holes.append((left, right, bottom, top)) }
            }
        }
        let xCuts = Array(Set([Float(0), length] + holes.flatMap { [$0.left, $0.right] })).sorted()
        let yCuts = Array(Set([Float(0), source.height] + holes.flatMap { [$0.bottom, $0.top] })).sorted()
        let material = SimpleMaterial(color: UIColor(white: 0.92, alpha: 1), roughness: 0.85, isMetallic: false)
        for column in 0..<(xCuts.count - 1) {
            for row in 0..<(yCuts.count - 1) {
                let x = (xCuts[column] + xCuts[column + 1]) / 2
                let y = (yCuts[row] + yCuts[row + 1]) / 2
                guard !holes.contains(where: { x > $0.left && x < $0.right && y > $0.bottom && y < $0.top }) else { continue }
                let width = xCuts[column + 1] - xCuts[column]
                let height = yCuts[row + 1] - yCuts[row]
                guard width > 0.01, height > 0.01 else { continue }
                let panel = ModelEntity(mesh: .generateBox(size: [width, height, 0.08]), materials: [material])
                panel.name = "ScannedWall\(index)_\(column)_\(row)"
                panel.position = [start.x + direction.x * x, y, start.y + direction.y * x]
                panel.orientation = simd_quatf(angle: atan2(-direction.y, direction.x), axis: [0, 1, 0])
                panel.components.set(DynamicLightShadowComponent(castsShadow: true))
                shell.addChild(panel)
            }
        }
    }

    // MARK: - Camera

    func setOrbit(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = min(1.35, max(0.15, pitch))
        updateCamera()
    }

    func setDistance(_ value: Float) {
        distance = min(roomExtent * 5, max(roomExtent * 0.6, value))
        updateCamera()
    }

    private func updateCamera() {
        let target = cameraTarget
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

    // MARK: - Finding the window in the model

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
