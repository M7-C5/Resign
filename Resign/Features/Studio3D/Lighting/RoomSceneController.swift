import RealityKit
import Observation
import UIKit
import simd

/// Loads the scanned Room.usdz (with Room-2.usdz colored mock fallback) or parametric scanned layout,
/// instantiates sanitized furniture, centers the camera dynamically on the room centroid,
/// and manages the lighting rig, PBR architectural styling, and selection visuals.
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
        self.simulationLayout = simulationLayout ?? layout.map { RoomSimulationLayout(layout: $0) }
        rig = RoomLightingRig(fixtures: fixtures)
        root.name = layout == nil ? "MockRoomRoot" : "RoomSceneRoot"

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

    /// Puts the scene into an ARView (non-AR) and creates the lights.
    func install(in view: ARView) {
        rig.buildIfNeeded()
        if let simLayout = simulationLayout {
            rig.configure(openings: simLayout.windows, roomCenter: [0, simLayout.height * 0.65, 0])
        }
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(root)
        view.scene.addAnchor(anchor)
    }

    func load() async {
        guard roomEntity == nil, loadState != .loading else { return }
        loadState = .loading
        do {
            let url: URL
            if let layout, let usdzURL = layout.usdzURL, FileManager.default.fileExists(atPath: usdzURL.path) {
                url = usdzURL
            } else if let simLayout = simulationLayout, let modelURL = simLayout.modelURL, FileManager.default.fileExists(atPath: modelURL.path) {
                url = modelURL
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
            root.addChild(loaded)
            roomEntity = loaded

            // Derive authentic floor level and interior drywall limits
            let bounds = loaded.visualBounds(relativeTo: root)
            let cx = (bounds.min.x + bounds.max.x) * 0.5
            let cz = (bounds.min.z + bounds.max.z) * 0.5

            var interiorMinX = bounds.min.x
            var interiorMaxX = bounds.max.x
            var interiorMinZ = bounds.min.z
            var interiorMaxZ = bounds.max.z

            if let archGrp = loaded.findEntity(named: "Arch_grp") {
                for child in archGrp.children where child.name.lowercased().contains("wall") {
                    let b = child.visualBounds(relativeTo: root)
                    let extentX = b.max.x - b.min.x
                    let extentZ = b.max.z - b.min.z
                    let midX = (b.min.x + b.max.x) * 0.5
                    let midZ = (b.min.z + b.max.z) * 0.5

                    if extentZ > extentX {
                        // North-South running wall (East or West boundary)
                        if midX > cx {
                            interiorMaxX = min(interiorMaxX, b.min.x)
                        } else {
                            interiorMinX = max(interiorMinX, b.max.x)
                        }
                    } else {
                        // East-West running wall (North or South boundary)
                        if midZ > cz {
                            interiorMaxZ = min(interiorMaxZ, b.min.z)
                        } else {
                            interiorMinZ = max(interiorMinZ, b.max.z)
                        }
                    }
                }
            }

            self.roomHorizontalBounds = (interiorMinX, interiorMaxX, interiorMinZ, interiorMaxZ)

            if let floorGrp = loaded.findEntity(named: "Floor_grp") {
                let floorBounds = floorGrp.visualBounds(relativeTo: root)
                self.floorLevel = floorBounds.center.y
            } else {
                self.floorLevel = bounds.min.y
            }

            // Center camera target on the true geometric room center
            self.cameraTarget = SIMD3<Float>(
                (interiorMinX + interiorMaxX) * 0.5,
                self.floorLevel + 0.8,
                (interiorMinZ + interiorMaxZ) * 0.5
            )
            let span = max(interiorMaxX - interiorMinX, interiorMaxZ - interiorMinZ)
            self.distance = min(18, max(5, span * 1.6))
            updateCamera()

            // Populate sanitized furniture from layout or synthesize mock layout furniture
            populateFurnitures()

            let opening = findWindow(in: loaded)
            if let opening {
                rig.configure(opening: opening)
            } else if let simLayout = simulationLayout {
                rig.configure(openings: simLayout.windows, roomCenter: cameraTarget)
            }
            loadState = .loaded
        } catch is CancellationError {
            loadState = .idle
        } catch {
            loadState = .failed
        }
    }

    func reload() async {
        roomEntity?.removeFromParent()
        roomEntity = nil
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
            for furniture in layout.furnitures {
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

    private func createMockFurnitureItems(at floorY: Float) -> [Furniture] {
        [
            Furniture(name: "Queen Bed", category: "bed", positionX: -1.79, positionY: floorY, positionZ: -1.10, rotationYaw: 0, length: 2.0, width: 1.6, height: 0.9),
            Furniture(name: "Work Desk", category: "desk", positionX: 0.05, positionY: floorY, positionZ: -0.55, rotationYaw: .pi / 2, length: 1.4, width: 0.7, height: 0.75),
            Furniture(name: "Desk Chair", category: "chair", positionX: -0.15, positionY: floorY, positionZ: -0.52, rotationYaw: -.pi / 2, length: 0.6, width: 0.6, height: 0.9),
            Furniture(name: "Sofa", category: "sofa", positionX: -1.20, positionY: floorY, positionZ: 0.95, rotationYaw: 0, length: 2.0, width: 0.85, height: 0.8),
            Furniture(name: "Wardrobe", category: "storage", positionX: -0.83, positionY: floorY, positionZ: -1.75, rotationYaw: 0, length: 1.2, width: 0.6, height: 2.0)
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

    // MARK: - Camera

    func setOrbit(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = min(0.95, max(0.30, pitch))
        updateCamera()
    }

    func setDistance(_ value: Float) {
        distance = min(24, max(5, value))
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
