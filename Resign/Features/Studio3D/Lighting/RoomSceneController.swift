import RealityKit
import Observation
import UIKit
import simd

/// Registered wall entity with horizontal outward normal vector for dynamic cutaway rendering.
public struct WallCutawayItem: Sendable {
    public let entity: Entity
    public let outwardNormal: SIMD2<Float>

    public init(entity: Entity, outwardNormal: SIMD2<Float>) {
        self.entity = entity
        self.outwardNormal = outwardNormal
    }
}

/// Loads the scanned Room.usdz (with Room-2.usdz colored mock fallback) or parametric scanned layout,
/// instantiates sanitized furniture, centers the camera dynamically on the room centroid,
/// and manages the lighting rig, PBR architectural styling, selection visuals, viewport presets, and cutaways.
@MainActor
@Observable
final class RoomSceneController {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var loadState: LoadState = .idle
    private(set) var resolvedWindowAzimuths: [Double]?
    public private(set) var floorLevel: Float = 0.0
    public private(set) var roomHorizontalBounds: (minX: Float, maxX: Float, minZ: Float, maxZ: Float)? = nil
    public private(set) var wallCutaways: [WallCutawayItem] = []

    let root = Entity()
    let rig: RoomLightingRig
    private let camera = PerspectiveCamera()
    private let architecturalKeyLight = DirectionalLight()
    private let architecturalFillLight = DirectionalLight()
    private var roomEntity: Entity?
    private var furnitureEntities: [UUID: Entity] = [:]

    private(set) var room: Room?
    private(set) var layout: Layout?
    private let simulationLayout: RoomSimulationLayout?

    @ObservationIgnored private var cameraTarget: SIMD3<Float> = [0, 1.2, 0]
    @ObservationIgnored private var roomExtent: Float = 5
    @ObservationIgnored private var animationTask: Task<Void, Never>?

    // Orbit state. Comfortable dollhouse perspective
    @ObservationIgnored var yaw: Float = -0.73
    @ObservationIgnored var pitch: Float = 0.62
    @ObservationIgnored var distance: Float = 10

    init(
        room: Room? = nil,
        layout: Layout? = nil,
        fixtures: [RoomLightingFixture]? = nil,
        simulationLayout: RoomSimulationLayout? = nil
    ) {
        self.room = room
        self.layout = layout
        self.simulationLayout = simulationLayout
        rig = RoomLightingRig(fixtures: fixtures)
        root.name = (layout == nil && simulationLayout == nil) ? "MockRoomRoot" : "ScannedRoomRoot"

        let span = max(room?.width ?? 4.0, room?.length ?? 4.0)
        distance = min(20, max(5, span * 1.6))

        // Non-AR environment lighting setup
        root.components.set(EnvironmentLightingConfigurationComponent(environmentLightingWeight: 0))
        root.components.set(ImageBasedLightComponent(source: .none))
        root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        camera.camera.fieldOfViewInDegrees = 40
        camera.camera.near = 0.1
        camera.camera.far = 60
        root.addChild(rig.root)
        root.addChild(camera)

        // Architectural ambient and key directional lighting for crystal-clear dollhouse visibility
        architecturalKeyLight.name = "ArchitecturalKeyLight"
        architecturalKeyLight.light.color = UIColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1.0)
        architecturalKeyLight.light.intensity = 2200
        architecturalKeyLight.look(at: .zero, from: [2, 5, 3], relativeTo: nil)
        root.addChild(architecturalKeyLight)

        architecturalFillLight.name = "ArchitecturalFillLight"
        architecturalFillLight.light.color = UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1.0)
        architecturalFillLight.light.intensity = 1400
        architecturalFillLight.look(at: .zero, from: [-3, 4, -3], relativeTo: nil)
        root.addChild(architecturalFillLight)

        if let simLayout = self.simulationLayout {
            pitch = 0.9
            roomExtent = max(simLayout.width, simLayout.length)
        }

        updateCamera()
    }

    convenience init(fixtures: [RoomLightingFixture]? = nil, layout: RoomSimulationLayout? = nil) {
        self.init(room: nil, layout: nil, fixtures: fixtures, simulationLayout: layout)
    }

    func setLightingFixtures(_ fixtures: [RoomLightingFixture]?) {
        rig.setFixtures(fixtures)
    }

    func setRoomAndLayout(room: Room?, layout: Layout?) {
        self.room = room
        self.layout = layout
        let span = max(room?.width ?? 4.0, room?.length ?? 4.0)
        distance = min(20, max(5, span * 1.6))
    }

    private(set) weak var arView: ARView?

    /// Puts the scene into an ARView (non-AR) and creates the lights.
    func install(in view: ARView) {
        self.arView = view
        rig.buildIfNeeded()
        if let simLayout = simulationLayout {
            rig.configure(openings: simLayout.windows, roomCenter: [0, simLayout.height * 0.65, 0])
        }
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(root)
        view.scene.addAnchor(anchor)
    }

    /// Raycasts from a screen point onto the authentic floor plane.
    func projectToFloor(from screenPoint: CGPoint) -> SIMD3<Float>? {
        guard let view = arView, let ray = view.ray(through: screenPoint) else { return nil }
        guard abs(ray.direction.y) > 1e-4 else { return nil }
        let t = (floorLevel - ray.origin.y) / ray.direction.y
        guard t > 0 else { return nil }
        return ray.origin + t * ray.direction
    }

    func load() async {
        guard roomEntity == nil, loadState != .loading else { return }
        loadState = .loading
        do {
            if let simLayout = simulationLayout {
                try await loadScannedLayout(simLayout)
                loadState = .loaded
                return
            }

            let url: URL
            if let layout, let usdzURL = layout.usdzURL, FileManager.default.fileExists(atPath: usdzURL.path) {
                url = usdzURL
            } else if layout != nil, let room2URL = Bundle.main.url(forResource: "Room-2", withExtension: "usdz") {
                // High-fidelity colored mock room reference environment for layouts
                url = room2URL
            } else if let testBundleURL = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") {
                // Headless unit test harness reference environment (ADR 0004)
                url = testBundleURL
            } else if let room2URL = Bundle.main.url(forResource: "Room-2", withExtension: "usdz") {
                url = room2URL
            } else {
                throw CocoaError(.fileNoSuchFile)
            }

            let loaded = try await Entity(contentsOf: url)
            try Task.checkCancellation()
            prepare(loaded)
            applyArchitecturalStyling(to: loaded)

            // Derive dominant wall tilt to align room walls squarely with world X and Z axes
            let dominantTilt = dominantWallTilt(in: loaded)

            let captureSpace = Entity()
            captureSpace.name = "CaptureSpace"
            captureSpace.orientation = simd_quatf(angle: dominantTilt, axis: [0, 1, 0])
            captureSpace.addChild(loaded)

            let normalizedRoom = Entity()
            normalizedRoom.name = "NormalizedRoom"
            normalizedRoom.addChild(captureSpace)

            // Derive floor level and center in straightened coordinates
            let rotatedBounds = loaded.visualBounds(relativeTo: normalizedRoom)
            let cx = (rotatedBounds.min.x + rotatedBounds.max.x) * 0.5
            let cz = (rotatedBounds.min.z + rotatedBounds.max.z) * 0.5

            let rawFloorY: Float
            if let floorGrp = loaded.findEntity(named: "Floor_grp") {
                rawFloorY = floorGrp.visualBounds(relativeTo: normalizedRoom).center.y
            } else {
                rawFloorY = rotatedBounds.min.y
            }

            // Center room horizontally at (0, 0) and ground floor at Y = 0.0
            captureSpace.position = [-cx, -rawFloorY, -cz]

            root.addChild(normalizedRoom)
            roomEntity = normalizedRoom
            self.floorLevel = 0.0

            // Derive authentic interior drywall limits and wall cutaways in centered space
            var wallCutawayList: [WallCutawayItem] = []
            let wallCandidates: [Entity]
            if let archGrp = loaded.findEntity(named: "Arch_grp") {
                wallCandidates = archGrp.children.filter { $0.name.lowercased().contains("wall") }
            } else {
                func collectWalls(in entity: Entity) -> [Entity] {
                    var list: [Entity] = []
                    if entity.name.lowercased().contains("wall") { list.append(entity) }
                    for child in entity.children { list.append(contentsOf: collectWalls(in: child)) }
                    return list
                }
                wallCandidates = collectWalls(in: loaded)
            }

            let centeredBounds = normalizedRoom.visualBounds(relativeTo: root)
            var interiorMinX = centeredBounds.min.x
            var interiorMaxX = centeredBounds.max.x
            var interiorMinZ = centeredBounds.min.z
            var interiorMaxZ = centeredBounds.max.z

            for child in wallCandidates {
                let b = child.visualBounds(relativeTo: root)
                let extentX = b.max.x - b.min.x
                let extentZ = b.max.z - b.min.z
                let midX = (b.min.x + b.max.x) * 0.5
                let midZ = (b.min.z + b.max.z) * 0.5

                let normal: SIMD2<Float>
                if extentZ > extentX {
                    // North-South running wall (East or West boundary)
                    if midX > 0 {
                        interiorMaxX = min(interiorMaxX, b.min.x)
                        normal = SIMD2<Float>(1, 0)
                    } else {
                        interiorMinX = max(interiorMinX, b.max.x)
                        normal = SIMD2<Float>(-1, 0)
                    }
                } else {
                    // East-West running wall (North or South boundary)
                    if midZ > 0 {
                        interiorMaxZ = min(interiorMaxZ, b.min.z)
                        normal = SIMD2<Float>(0, 1)
                    } else {
                        interiorMinZ = max(interiorMinZ, b.max.z)
                        normal = SIMD2<Float>(0, -1)
                    }
                }
                wallCutawayList.append(WallCutawayItem(entity: child, outwardNormal: normal))
            }

            self.wallCutaways = wallCutawayList
            self.roomHorizontalBounds = (interiorMinX, interiorMaxX, interiorMinZ, interiorMaxZ)

            // Center camera target on the true geometric room center (0, 0.8, 0)
            self.cameraTarget = SIMD3<Float>(
                (interiorMinX + interiorMaxX) * 0.5,
                self.floorLevel + 0.8,
                (interiorMinZ + interiorMaxZ) * 0.5
            )
            let span = max(interiorMaxX - interiorMinX, interiorMaxZ - interiorMinZ)
            self.distance = min(18, max(5, span * 1.6))
            updateCamera()
            updateWallCutaways()

            // Populate sanitized furniture from layout or synthesize mock layout furniture
            populateFurnitures()

            let opening = findWindow(in: loaded)
            if let opening {
                rig.configure(opening: opening)
            }
            loadState = .loaded
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
        var effectiveYaw = source.yaw
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
            if source.scanPlan == nil && abs(effectiveYaw) < 0.001 {
                let tilt = dominantWallTilt(in: shell)
                if abs(tilt) > 0.001 {
                    effectiveYaw = -tilt
                }
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
                furnitureEntities[item.id] = entity
            }
        }
        let inverseYaw = simd_quatf(angle: -effectiveYaw, axis: [0, 1, 0])
        captureSpace.orientation = inverseYaw
        captureSpace.position = inverseYaw.act([-source.center.x, -source.floorLevel, -source.center.y])

        try Task.checkCancellation()
        root.addChild(normalizedRoom)
        roomEntity = normalizedRoom
        rig.configure(openings: source.windows, roomCenter: [0, source.height * 0.65, 0])
        resolvedWindowAzimuths = source.windowAzimuths
        let bounds = normalizedRoom.visualBounds(relativeTo: root)
        roomExtent = max(2, max(bounds.extents.x, max(bounds.extents.z, source.height)))
        cameraTarget = [bounds.center.x, source.height * 0.35, bounds.center.z]
        distance = roomExtent * 1.9
        camera.camera.far = max(60, distance * 5)
        floorLevel = 0.0
        roomHorizontalBounds = (
            minX: -source.width / 2.0,
            maxX: source.width / 2.0,
            minZ: -source.length / 2.0,
            maxZ: source.length / 2.0
        )
        updateCamera()
        updateWallCutaways()
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
        var scannedCutaways: [WallCutawayItem] = []
        for (index, wall) in walls.enumerated() {
            if let group = addWall(wall, index: index, source: source, to: shell) {
                let delta = SIMD2<Float>(wall.endX - wall.startX, wall.endZ - wall.startZ)
                let len = simd_length(delta)
                if len > 0.02 {
                    let tangent = delta / len
                    var normal = simd_normalize(SIMD2<Float>(tangent.y, -tangent.x))
                    let mid = SIMD2<Float>((wall.startX + wall.endX) * 0.5, (wall.startZ + wall.endZ) * 0.5)
                    if simd_dot(normal, mid) < 0 { normal = -normal }
                    scannedCutaways.append(WallCutawayItem(entity: group, outwardNormal: normal))
                }
            }
        }
        self.wallCutaways = scannedCutaways
        return shell
    }

    @discardableResult
    private func addWall(_ wall: RoomPlanSnapshot.WallSegment, index: Int, source: RoomSimulationLayout, to shell: Entity) -> Entity? {
        let start = SIMD2<Float>(wall.startX, wall.startZ)
        let delta = SIMD2<Float>(wall.endX - wall.startX, wall.endZ - wall.startZ)
        let length = simd_length(delta)
        guard length > 0.02 else { return nil }
        let direction = delta / length
        let wallGroup = Entity()
        wallGroup.name = "ApertureWallGroup\(index)"
        // Partition the wall into solid panels around every saved opening.
        var holes: [(left: Float, right: Float, bottom: Float, top: Float)] = []
        for aperture in source.apertures {
            let p = source.localPosition(aperture.position)
            let rel = SIMD2<Float>(p.x - start.x, p.z - start.y)
            let projection = simd_dot(rel, direction)
            let distance = abs(rel.x * direction.y - rel.y * direction.x)
            if projection > -0.2 && projection < length + 0.2 && distance < 0.35 {
                let left = max(0, projection - aperture.width / 2)
                let right = min(length, projection + aperture.width / 2)
                let bottom = max(0, p.y - aperture.height / 2)
                let top = min(source.height, p.y + aperture.height / 2)
                if right > left && top > bottom { holes.append((left, right, bottom, top)) }
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
                wallGroup.addChild(panel)
            }
        }
        shell.addChild(wallGroup)
        return wallGroup
    }

    func reload() async {
        animationTask?.cancel()
        roomEntity?.removeFromParent()
        roomEntity = nil
        wallCutaways.removeAll()
        for (_, entity) in furnitureEntities {
            entity.removeFromParent()
        }
        furnitureEntities.removeAll()
        loadState = .idle
        await load()
    }

    // MARK: - Furniture Management

    private func populateFurnitures() {
        if let layout, !layout.furnitures.isEmpty {
            for furniture in layout.furnitures where !furniture.isArchived {
                let entity = FurnitureEntityFactory.createEntity(for: furniture)
                // Ensure furniture is grounded to the authentic floor level
                if abs(entity.position.y) < 0.05 && floorLevel != 0 {
                    entity.position.y = floorLevel
                }
                furnitureEntities[furniture.id] = entity
                root.addChild(entity)
            }
        } else {
            // Seed authentic furniture into mock room environment grounded at floorLevel
            let mockItems = createMockFurnitureItems(at: floorLevel)
            for item in mockItems {
                let entity = FurnitureEntityFactory.createEntity(for: item)
                furnitureEntities[item.id] = entity
                root.addChild(entity)
                layout?.furnitures.append(item)
            }
        }
    }

    func archiveFurnitureEntity(id: UUID) {
        guard let entity = furnitureEntities.removeValue(forKey: id) else { return }
        entity.removeFromParent()
    }

    func spawnRestoredFurnitureEntity(for furniture: Furniture) {
        if let existing = furnitureEntities.removeValue(forKey: furniture.id) {
            existing.removeFromParent()
        }
        let entity = FurnitureEntityFactory.createEntity(for: furniture)
        if abs(entity.position.y) < 0.05 && floorLevel != 0 {
            entity.position.y = floorLevel
        }
        furnitureEntities[furniture.id] = entity
        root.addChild(entity)
    }

    func setGhostOpacity(for id: UUID, isGhosted: Bool) {
        guard let entity = furnitureEntities[id] else { return }
        func applyOpacity(to ent: Entity) {
            if let model = ent as? ModelEntity, ent.name != "SelectionHalo" && !ent.name.hasPrefix("FurnitureRotationHandle") {
                if let materials = model.model?.materials {
                    var updatedMaterials: [RealityKit.Material] = []
                    for mat in materials {
                        if let sim = mat as? SimpleMaterial {
                            var updated = sim
                            let alpha: CGFloat = isGhosted ? 0.35 : 1.0
                            updated.color = .init(tint: sim.color.tint.withAlphaComponent(alpha), texture: sim.color.texture)
                            updatedMaterials.append(updated)
                        } else {
                            updatedMaterials.append(mat)
                        }
                    }
                    model.model?.materials = updatedMaterials
                }
            }
            for child in ent.children {
                applyOpacity(to: child)
            }
        }
        applyOpacity(to: entity)
    }

    private func createMockFurnitureItems(at floorY: Float) -> [Furniture] {
        [
            Furniture(name: "Queen Bed", category: "bed", positionX: -0.75, positionY: floorY, positionZ: -0.65, rotationYaw: 0, length: 2.0, width: 1.6, height: 0.9),
            Furniture(name: "Work Desk", category: "desk", positionX: 1.30, positionY: floorY, positionZ: 0.0, rotationYaw: 0, length: 1.4, width: 0.7, height: 0.75),
            Furniture(name: "Desk Chair", category: "chair", positionX: 0.60, positionY: floorY, positionZ: 0.0, rotationYaw: -.pi / 2, length: 0.6, width: 0.6, height: 0.9),
            Furniture(name: "Sofa", category: "sofa", positionX: -0.30, positionY: floorY, positionZ: 1.30, rotationYaw: .pi / 2, length: 2.0, width: 0.85, height: 0.8),
            Furniture(name: "Wardrobe", category: "storage", positionX: 0.95, positionY: floorY, positionZ: -1.45, rotationYaw: .pi / 2, length: 1.2, width: 0.6, height: 2.0)
        ]
    }

    func setSelection(furnitureID: UUID?, isColliding: Bool = false) {
        for (id, entity) in furnitureEntities {
            FurnitureEntityFactory.updateSelectionVisual(
                on: entity,
                isSelected: id == furnitureID,
                isColliding: isColliding
            )
        }
    }

    func updateFurnitureTransform(id: UUID, position: SIMD3<Float>, yaw: Float) {
        guard let entity = furnitureEntities[id] else { return }
        entity.position = position
        entity.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }

    func furnitureEntity(for id: UUID) -> Entity? {
        furnitureEntities[id]
    }

    // MARK: - Viewport Snapping & Cutaways

    /// Snaps the orbit camera to an architectural viewport preset, optionally interpolating smoothly.
    func snapToViewport(_ preset: ViewportPreset, animated: Bool = true) {
        let startYaw = self.yaw
        let startPitch = self.pitch
        let targetYaw = preset.targetYaw
        let targetPitch = preset.targetPitch

        if !animated {
            animationTask?.cancel()
            setOrbit(yaw: targetYaw, pitch: targetPitch)
            return
        }

        animationTask?.cancel()
        animationTask = Task { @MainActor in
            let duration: Double = 0.35
            let startTime = CACurrentMediaTime()

            var deltaYaw = (targetYaw - startYaw).truncatingRemainder(dividingBy: .pi * 2)
            if deltaYaw > .pi { deltaYaw -= .pi * 2 }
            if deltaYaw < -.pi { deltaYaw += .pi * 2 }

            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1.0, elapsed / duration)
                let t = Float(progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2)

                let currentYaw = startYaw + deltaYaw * t
                let currentPitch = startPitch + (targetPitch - startPitch) * t
                setOrbit(yaw: currentYaw, pitch: currentPitch)

                if progress >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    /// Evaluates dynamic wall cutaways based on camera orbit position.
    /// In top-down bird's-eye view (pitch >= 1.05 rad / ~60°), all perimeter walls stay visible.
    /// At side angles (pitch < 1.05 rad), walls whose normal points toward the camera (dot > 0.1) are hidden.
    func updateWallCutaways() {
        if pitch >= 1.05 {
            for item in wallCutaways {
                item.entity.isEnabled = true
            }
            return
        }

        let camDir = SIMD2<Float>(sin(yaw), cos(yaw))

        for item in wallCutaways {
            let isFacingCamera = simd_dot(item.outwardNormal, camDir) > 0.1
            item.entity.isEnabled = !isFacingCamera
        }
    }

    // MARK: - Camera

    func setOrbit(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = min(1.56, max(0.10, pitch))
        updateCamera()
        updateWallCutaways()
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

    // MARK: - Model preparation & Architectural Styling

    /// Cutaway ceiling, wireframe bounding box object groups, and configure dynamic shadows.
    private func prepare(_ entity: Entity) {
        let name = entity.name
        if name == "Ceiling" || name.contains("Object_grp") || name.hasPrefix("Object_") || name == "Door" {
            entity.isEnabled = false
        }
        if entity.components.has(ModelComponent.self) {
            entity.components.set(DynamicLightShadowComponent(castsShadow: castsShadow(named: name)))
        }
        for child in entity.children {
            prepare(child)
        }
    }

    /// Applies warm architectural PBR finishes to natural oak floor and matte drywall.
    private func applyArchitecturalStyling(to roomShell: Entity) {
        let wallMaterial = SimpleMaterial(
            color: UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1.0),
            roughness: 0.85,
            isMetallic: false
        )
        let floorMaterial = SimpleMaterial(
            color: UIColor(red: 0.76, green: 0.60, blue: 0.44, alpha: 1.0),
            roughness: 0.45,
            isMetallic: false
        )

        // Style floors with warm natural oak
        if let floorGrp = roomShell.findEntity(named: "Floor_grp") {
            assignMaterial(floorMaterial, toDescendantsOf: floorGrp)
        }

        // Style walls with matte drywall while preserving door and window frames
        if let archGrp = roomShell.findEntity(named: "Arch_grp") {
            for child in archGrp.children where child.name.lowercased().contains("wall") {
                assignMaterial(
                    wallMaterial,
                    toDescendantsOf: child,
                    filter: { entity in
                        let name = entity.name.lowercased()
                        return !name.contains("door") && !name.contains("window")
                    }
                )
            }
        }
    }

    private func assignMaterial(
        _ material: RealityKit.Material,
        toDescendantsOf entity: Entity,
        filter: ((Entity) -> Bool)? = nil
    ) {
        if filter?(entity) ?? true {
            if var model = entity.components[ModelComponent.self] {
                model.materials = [material]
                entity.components.set(model)
            }
        }
        for child in entity.children {
            assignMaterial(material, toDescendantsOf: child, filter: filter)
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

    /// Uses the bounds of the mesh(es) named "glass" on the perimeter walls as the window opening.
    private func findWindow(in model: Entity) -> WindowOpening? {
        let glass = modelEntities(in: model).filter { $0.name.lowercased().contains("glass") }
        guard let box = union(glass.map { $0.visualBounds(relativeTo: root) }), abs(box.center.x) > 0.8 || abs(box.center.z) > 0.8 else {
            return nil
        }
        return WindowOpening(center: box.center, width: box.extents.z, height: box.extents.y)
    }

    /// Derives the dominant wall orientation deviation relative to coordinate axes so the room can be un-tilted.
    private func dominantWallTilt(in loaded: Entity) -> Float {
        var wallModels: [Entity] = []
        func collectWalls(in entity: Entity) {
            if entity.name.lowercased().contains("wall"), entity.components.has(ModelComponent.self) {
                wallModels.append(entity)
            }
            for child in entity.children {
                collectWalls(in: child)
            }
        }
        collectWalls(in: loaded)

        var candidateAngles: [Float] = []
        for wall in wallModels {
            let orient = wall.orientation(relativeTo: loaded)
            let dir = orient.act(SIMD3<Float>(1, 0, 0))
            if abs(dir.x) > 0.001 || abs(dir.z) > 0.001 {
                let angle = atan2(dir.z, dir.x)
                let diff = normalizeQuarterTurn(angle)
                candidateAngles.append(diff)
            }
        }

        guard !candidateAngles.isEmpty else { return 0.0 }
        candidateAngles.sort()
        return candidateAngles[candidateAngles.count / 2]
    }

    private func normalizeQuarterTurn(_ angle: Float) -> Float {
        let quarter = Float.pi / 2.0
        var rem = angle.truncatingRemainder(dividingBy: quarter)
        if rem > quarter / 2.0 {
            rem -= quarter
        } else if rem < -quarter / 2.0 {
            rem += quarter
        }
        return rem
    }

    /// Glass and anything that looks like a lamp must not cast shadows,
    /// otherwise a fixture mesh wrapped around a light source blocks all of its light.
    private func castsShadow(named name: String) -> Bool {
        let lowered = name.lowercased()
        let nonCasters = ["glass", "light", "lamp", "fixture", "bulb"]
        return !nonCasters.contains { lowered.contains($0) }
    }
}
