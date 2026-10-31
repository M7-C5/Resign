import Observation
import SwiftData
import simd
import Foundation
import CoreGraphics

/// A floor-level operational clearance highlight for furniture involved in a spatial violation.
public struct ViolationMarker: Identifiable, Hashable, Sendable {
    public var id: String
    public var ruleId: String
    public var title: String
    public var severity: ViolationSeverity
    public var measuredCm: Double
    public var requiredCm: Double
    /// Room-space footprint in meters (same frame as `Furniture` positions).
    public var centerX: Float
    public var centerZ: Float
    public var sizeX: Float
    public var sizeZ: Float
    /// Clearance operational zone radius in meters.
    public var clearanceRadius: Float

    // Contextual Door Swing Geometry
    public var isDoorSwing: Bool
    public var doorPivotX: Float
    public var doorPivotZ: Float
    public var doorSwingRadius: Float
    public var doorStartAngle: Float
    public var doorSweepAngle: Float

    public init(
        id: String,
        ruleId: String,
        title: String,
        severity: ViolationSeverity,
        measuredCm: Double,
        requiredCm: Double,
        centerX: Float,
        centerZ: Float,
        sizeX: Float,
        sizeZ: Float,
        clearanceRadius: Float = 0.85,
        isDoorSwing: Bool = false,
        doorPivotX: Float = 0,
        doorPivotZ: Float = 0,
        doorSwingRadius: Float = 0.9,
        doorStartAngle: Float = 0,
        doorSweepAngle: Float = -Float.pi / 2.0
    ) {
        self.id = id
        self.ruleId = ruleId
        self.title = title
        self.severity = severity
        self.measuredCm = measuredCm
        self.requiredCm = requiredCm
        self.centerX = centerX
        self.centerZ = centerZ
        self.sizeX = sizeX
        self.sizeZ = sizeZ
        self.clearanceRadius = clearanceRadius
        self.isDoorSwing = isDoorSwing
        self.doorPivotX = doorPivotX
        self.doorPivotZ = doorPivotZ
        self.doorSwingRadius = doorSwingRadius
        self.doorStartAngle = doorStartAngle
        self.doorSweepAngle = doorSweepAngle
    }
}

/// Holds the confirmed lighting, the draft being edited in the sheet,
/// and the interactive 3D furniture selection and rearrangement state.
@Observable
@MainActor
public final class Studio3DViewModel {
    // MARK: - Spatial Insights & Violation Highlighting State
    public var highlightedFurnitureIDs: Set<UUID> = []
    public var violationMarkers: [ViolationMarker] = []
    public var showViolations: Bool = true
    public var currentLayout: Layout? = nil
    public var shouldAnimateLayoutChange: Bool = true
    public var activeLayoutVersion: Int = 0

    private(set) var lightingSettings = LightingSimulationSettings(previewMode: .layoutOnly)
    var lightingDraft = LightingSimulationSettings(previewMode: .layoutOnly)
    var isLightingPresented = false

    // MARK: - Furniture Rearrangement State
    public var selectedFurnitureID: UUID? = nil
    public var isDraggingFurniture = false
    public var isColliding = false
    public var roomHorizontalBounds: (minX: Float, maxX: Float, minZ: Float, maxZ: Float)? = nil
    public var roomWallSegments: [RoomPlanSnapshot.WallSegment] = []

    // MARK: - Inventory State
    public var isInventoryOpen = false
    public var isHoveringArchiveTarget = false
    public var archiveTargetCenter: CGPoint? = nil

    @ObservationIgnored
    private var lastCommittedPositions: [UUID: (position: SIMD3<Float>, yaw: Float)] = [:]

    /// While the sheet is open the room previews the draft; otherwise the confirmed settings.
    var previewLighting: LightingSimulationSettings {
        isLightingPresented ? lightingDraft : lightingSettings
    }

    var isSimulationEnabled: Bool { previewLighting.previewMode == .simulation }

    public init() {}

    // MARK: - Furniture Manipulation

    public func selectFurniture(id: UUID?, in layout: Layout? = nil) {
        selectedFurnitureID = id
        isColliding = false
        if let id, let layout, let furniture = layout.furnitures.first(where: { $0.id == id }) {
            lastCommittedPositions[id] = (
                SIMD3<Float>(furniture.positionX, furniture.positionY, furniture.positionZ),
                furniture.rotationYaw
            )
        }
    }

    public func deselectFurniture(in layout: Layout? = nil, context: ModelContext? = nil) {
        if isColliding, let id = selectedFurnitureID, let layout {
            // If colliding on deselect, revert to last valid non-colliding coordinates
            _ = revertToLastValidPosition(id: id, in: layout, context: context)
        }
        selectedFurnitureID = nil
        isDraggingFurniture = false
        isColliding = false
    }

    @discardableResult
    public func moveSelectedFurniture(
        to floorPos: SIMD2<Float>,
        in layout: Layout?,
        context: ModelContext?
    ) -> (position: SIMD3<Float>, isColliding: Bool)? {
        guard let selectedFurnitureID,
              let layout,
              let furniture = layout.furnitures.first(where: { $0.id == selectedFurnitureID }) else {
            return nil
        }

        // 1. Permissive movement: clamp within drywall walls (respecting actual room bounds)
        let clamped: SIMD2<Float>
        if let b = roomHorizontalBounds {
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: floorPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: furniture.rotationYaw,
                minX: b.minX,
                maxX: b.maxX,
                minZ: b.minZ,
                maxZ: b.maxZ,
                walls: roomWallSegments
            )
        } else {
            let roomWidth = layout.room?.width ?? 5.0
            let roomLength = layout.room?.length ?? 5.0
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: floorPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: furniture.rotationYaw,
                roomWidth: roomWidth,
                roomLength: roomLength
            )
        }

        let posY = max(0.0, furniture.positionY)
        let candidate = FurnitureCollisionProxy(
            id: furniture.id,
            category: furniture.category,
            position: SIMD3<Float>(clamped.x, posY, clamped.y),
            dimensions: SIMD3<Float>(furniture.width, furniture.height, furniture.length),
            rotationYaw: furniture.rotationYaw
        )

        let obstacles = layout.furnitures
            .filter { $0.id != furniture.id && !$0.isArchived }
            .map { f in
                FurnitureCollisionProxy(
                    id: f.id,
                    category: f.category,
                    position: SIMD3<Float>(f.positionX, max(0.0, f.positionY), f.positionZ),
                    dimensions: SIMD3<Float>(f.width, f.height, f.length),
                    rotationYaw: f.rotationYaw
                )
            }

        // 2. Evaluate obstacle collision without locking movement
        let colliding = obstacles.contains { obstacle in
            SpatialClearanceEngine.checkCollision(itemA: candidate, itemB: obstacle)
        }
        self.isColliding = colliding

        // Update live visual position
        furniture.positionX = clamped.x
        furniture.positionY = posY
        furniture.positionZ = clamped.y

        // 3. Only persist to SwiftData if placed in a valid, collision-free position
        if !colliding {
            lastCommittedPositions[furniture.id] = (candidate.position, furniture.rotationYaw)
            if let context {
                try? context.save()
            }
        }

        return (candidate.position, colliding)
    }

    @discardableResult
    public func rotateSelectedFurniture(
        to rawYaw: Float,
        in layout: Layout?,
        context: ModelContext?,
        snapThreshold: Float = 0.12
    ) -> (position: SIMD3<Float>, yaw: Float, isColliding: Bool, didSnap: Bool)? {
        guard let selectedFurnitureID,
              let layout,
              let furniture = layout.furnitures.first(where: { $0.id == selectedFurnitureID }) else {
            return nil
        }

        let snapResult = SpatialClearanceEngine.snapYaw(rawYaw: rawYaw, step: .pi / 2.0, threshold: snapThreshold)
        let targetYaw = snapResult.yaw

        let currentPos = SIMD2<Float>(furniture.positionX, furniture.positionZ)
        let clamped: SIMD2<Float>
        if let b = roomHorizontalBounds {
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: currentPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: targetYaw,
                minX: b.minX,
                maxX: b.maxX,
                minZ: b.minZ,
                maxZ: b.maxZ,
                walls: roomWallSegments
            )
        } else {
            let roomWidth = layout.room?.width ?? 5.0
            let roomLength = layout.room?.length ?? 5.0
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: currentPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: targetYaw,
                roomWidth: roomWidth,
                roomLength: roomLength
            )
        }

        let posY = max(0.0, furniture.positionY)
        let candidate = FurnitureCollisionProxy(
            id: furniture.id,
            category: furniture.category,
            position: SIMD3<Float>(clamped.x, posY, clamped.y),
            dimensions: SIMD3<Float>(furniture.width, furniture.height, furniture.length),
            rotationYaw: targetYaw
        )

        let obstacles = layout.furnitures
            .filter { $0.id != furniture.id && !$0.isArchived }
            .map { f in
                FurnitureCollisionProxy(
                    id: f.id,
                    category: f.category,
                    position: SIMD3<Float>(f.positionX, max(0.0, f.positionY), f.positionZ),
                    dimensions: SIMD3<Float>(f.width, f.height, f.length),
                    rotationYaw: f.rotationYaw
                )
            }

        let colliding = obstacles.contains { obstacle in
            SpatialClearanceEngine.checkCollision(itemA: candidate, itemB: obstacle)
        }
        self.isColliding = colliding

        furniture.positionX = clamped.x
        furniture.positionY = posY
        furniture.positionZ = clamped.y
        furniture.rotationYaw = targetYaw

        if !colliding {
            lastCommittedPositions[furniture.id] = (candidate.position, targetYaw)
            if let context {
                try? context.save()
            }
        }

        return (candidate.position, targetYaw, colliding, snapResult.didSnap)
    }

    @discardableResult
    public func rotateSelectedFurniture90(
        in layout: Layout?,
        context: ModelContext?
    ) -> (position: SIMD3<Float>, yaw: Float, isColliding: Bool)? {
        guard let selectedFurnitureID,
              let layout,
              let furniture = layout.furnitures.first(where: { $0.id == selectedFurnitureID }) else {
            return nil
        }

        let nextYaw = SpatialClearanceEngine.stepRotation90(currentYaw: furniture.rotationYaw)
        let currentPos = SIMD2<Float>(furniture.positionX, furniture.positionZ)
        let clamped: SIMD2<Float>
        if let b = roomHorizontalBounds {
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: currentPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: nextYaw,
                minX: b.minX,
                maxX: b.maxX,
                minZ: b.minZ,
                maxZ: b.maxZ,
                walls: roomWallSegments
            )
        } else {
            let roomWidth = layout.room?.width ?? 5.0
            let roomLength = layout.room?.length ?? 5.0
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: currentPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: nextYaw,
                roomWidth: roomWidth,
                roomLength: roomLength
            )
        }

        let candidate = FurnitureCollisionProxy(
            id: furniture.id,
            category: furniture.category,
            position: SIMD3<Float>(clamped.x, max(0.0, furniture.positionY), clamped.y),
            dimensions: SIMD3<Float>(furniture.width, furniture.height, furniture.length),
            rotationYaw: nextYaw
        )

        let obstacles = layout.furnitures
            .filter { $0.id != furniture.id && !$0.isArchived }
            .map { f in
                FurnitureCollisionProxy(
                    id: f.id,
                    category: f.category,
                    position: SIMD3<Float>(f.positionX, max(0.0, f.positionY), f.positionZ),
                    dimensions: SIMD3<Float>(f.width, f.height, f.length),
                    rotationYaw: f.rotationYaw
                )
            }

        let colliding = obstacles.contains { obstacle in
            SpatialClearanceEngine.checkCollision(itemA: candidate, itemB: obstacle)
        }
        self.isColliding = colliding

        furniture.rotationYaw = nextYaw
        furniture.positionX = clamped.x
        furniture.positionZ = clamped.y

        if !colliding {
            lastCommittedPositions[furniture.id] = (candidate.position, nextYaw)
            if let context {
                try? context.save()
            }
        }

        return (candidate.position, nextYaw, colliding)
    }

    @discardableResult
    public func revertToLastValidPosition(
        id: UUID,
        in layout: Layout,
        context: ModelContext?
    ) -> (position: SIMD3<Float>, yaw: Float)? {
        guard let furniture = layout.furnitures.first(where: { $0.id == id }),
              let last = lastCommittedPositions[id] else {
            return nil
        }

        furniture.positionX = last.position.x
        furniture.positionY = last.position.y
        furniture.positionZ = last.position.z
        furniture.rotationYaw = last.yaw
        isColliding = false

        if let context {
            try? context.save()
        }

        return last
    }

    // MARK: - Inventory & Archival

    public func activeFurnitures(in layout: Layout?) -> [Furniture] {
        guard let layout else { return [] }
        return layout.furnitures.filter { !$0.isArchived }
    }

    public func archivedFurnitures(in layout: Layout?) -> [Furniture] {
        guard let layout else { return [] }
        return layout.furnitures.filter { $0.isArchived }
    }

    public func archiveFurniture(id: UUID, in layout: Layout?, context: ModelContext?) {
        guard let layout, let furniture = layout.furnitures.first(where: { $0.id == id }) else { return }
        furniture.isArchived = true
        if selectedFurnitureID == id {
            selectedFurnitureID = nil
            isColliding = false
            isDraggingFurniture = false
        }
        if let context {
            try? context.save()
        }
    }

    @discardableResult
    public func restoreFurniture(
        id: UUID,
        to targetPos: SIMD2<Float>,
        in layout: Layout?,
        context: ModelContext?
    ) -> (position: SIMD3<Float>, isColliding: Bool)? {
        guard let layout, let furniture = layout.furnitures.first(where: { $0.id == id }) else { return nil }
        furniture.isArchived = false

        // Clamp to room bounds
        let clamped: SIMD2<Float>
        if let b = roomHorizontalBounds {
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: targetPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: furniture.rotationYaw,
                minX: b.minX,
                maxX: b.maxX,
                minZ: b.minZ,
                maxZ: b.maxZ,
                walls: roomWallSegments
            )
        } else {
            let roomWidth = layout.room?.width ?? 5.0
            let roomLength = layout.room?.length ?? 5.0
            clamped = SpatialClearanceEngine.clampToRoomBoundaries(
                position: targetPos,
                furnitureWidth: furniture.width,
                furnitureLength: furniture.length,
                rotationYaw: furniture.rotationYaw,
                roomWidth: roomWidth,
                roomLength: roomLength
            )
        }

        furniture.positionX = clamped.x
        furniture.positionZ = clamped.y
        selectFurniture(id: furniture.id, in: layout)

        // Evaluate collision against other active furnitures
        let candidate = FurnitureCollisionProxy(
            id: furniture.id,
            category: furniture.category,
            position: SIMD3<Float>(clamped.x, max(0.0, furniture.positionY), clamped.y),
            dimensions: SIMD3<Float>(furniture.width, furniture.height, furniture.length),
            rotationYaw: furniture.rotationYaw
        )
        let obstacles = layout.furnitures
            .filter { $0.id != furniture.id && !$0.isArchived }
            .map { f in
                FurnitureCollisionProxy(
                    id: f.id,
                    category: f.category,
                    position: SIMD3<Float>(f.positionX, max(0.0, f.positionY), f.positionZ),
                    dimensions: SIMD3<Float>(f.width, f.height, f.length),
                    rotationYaw: f.rotationYaw
                )
            }
        let colliding = obstacles.contains { obstacle in
            SpatialClearanceEngine.checkCollision(itemA: candidate, itemB: obstacle)
        }
        self.isColliding = colliding

        if !colliding {
            lastCommittedPositions[furniture.id] = (candidate.position, furniture.rotationYaw)
        }
        if let context {
            try? context.save()
        }

        return (candidate.position, colliding)
    }

    public nonisolated static func isWithinArchiveTarget(point: CGPoint, targetCenter: CGPoint, radius: CGFloat = 64.0) -> Bool {
        let dx = point.x - targetCenter.x
        let dy = point.y - targetCenter.y
        return (dx * dx + dy * dy) <= (radius * radius)
    }

    // MARK: - Lighting Simulation Session

    /// A new viewer remains neutral until the user explicitly enables simulation.
    func toggleLightingSimulation() {
        if isSimulationEnabled {
            discardLightingEditing()
            lightingSettings.previewMode = .layoutOnly
            lightingDraft = lightingSettings
        } else {
            lightingSettings.previewMode = .simulation
            beginLightingEditing()
        }
    }

    func beginLightingEditing() {
        lightingDraft = lightingSettings
        lightingDraft.previewMode = .simulation
        isLightingPresented = true
    }

    func confirmLightingEditing() {
        guard isLightingPresented else { return }
        lightingSettings = lightingDraft
        isLightingPresented = false
    }

    func discardLightingEditing() {
        lightingDraft = lightingSettings
        isLightingPresented = false
    }

    /// Called after any dismissal, including swipe down. The draft never outlives the sheet.
    func sheetDidDismiss() {
        lightingDraft = lightingSettings
    }

    func updateRoomHeading(_ degrees: Double) {
        let heading = NorthAlignmentCalibration.normalized(degrees)
        lightingSettings.solarContext.roomHeadingDegrees = heading
        lightingDraft.solarContext.roomHeadingDegrees = heading
    }

    func updateWindowDirections(_ degrees: [Double]) {
        lightingSettings.solarContext.windowLocalAzimuths = degrees
        lightingDraft.solarContext.windowLocalAzimuths = degrees
    }

    // MARK: - Spatial Diagnostics & Highlights

    /// Applies a layout to the 3D studio, moving furniture entities to match layout positions
    public func applyLayout(_ layout: Layout, animated: Bool = true) {
        self.currentLayout = layout
        self.shouldAnimateLayoutChange = animated
        self.activeLayoutVersion += 1
    }

    /// Sets vibrant floor clearance highlights for recommended layouts showing compliant operational zones.
    public func setRecommendationHighlights(for layout: Layout) {
        let engine = SpatialClearanceEngine()
        var markers: [ViolationMarker] = []

        for item in layout.furnitures where !item.isArchived {
            let box = engine.boundingBox(for: item)
            let buffer: Float = (item.category == "desk" || item.category == "bed") ? 0.35 : 0.20
            let marker = ViolationMarker(
                id: "optimal-\(item.id)",
                ruleId: "OPT",
                title: "\(item.name) Clear Operational Flow",
                severity: .warning,
                measuredCm: 90.0,
                requiredCm: 76.2,
                centerX: box.centerX,
                centerZ: box.centerZ,
                sizeX: box.width + buffer,
                sizeZ: box.length + buffer,
                clearanceRadius: max(box.width, box.length) * 0.55
            )
            markers.append(marker)
        }
        self.violationMarkers = markers
    }

    /// Builds operational clearance markers per furniture item involved in each violation,
    /// calculating exact door swing arc geometry when doors are provided.
    public func setViolations(_ violations: [SpatialViolation], in layout: Layout, doors: [RoomOpening] = []) {
        let engine = SpatialClearanceEngine()
        let furniture = Dictionary(layout.furnitures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        violationMarkers = violations.flatMap { violation in
            violation.itemIds.compactMap { furniture[$0] }.map { item in
                let box = engine.boundingBox(for: item)
                let footprintRadius = max(box.width, box.length) * 0.5
                let requiredBufferMeters = Float(violation.requiredClearanceCm / 100.0)
                let radius = max(footprintRadius + (requiredBufferMeters * 0.45), requiredBufferMeters)

                var isDoor = false
                var pivotX: Float = box.centerX
                var pivotZ: Float = box.centerZ
                var swingRad: Float = requiredBufferMeters > 0 ? requiredBufferMeters : 0.90
                var startAngle: Float = 0.0
                var sweepAngle: Float = -Float.pi / 2.0

                if violation.ruleId == PaneroZelnikRule.doorSwingUnobstructed {
                    isDoor = true
                    // Find the door closest to this obstructing furniture item
                    let matchedDoor = doors.min(by: { d1, d2 in
                        let dist1 = hypot(d1.posX - box.centerX, d1.posZ - box.centerZ)
                        let dist2 = hypot(d2.posX - box.centerX, d2.posZ - box.centerZ)
                        return dist1 < dist2
                    })

                    if let door = matchedDoor {
                        swingRad = door.width
                        if abs(door.posZ) >= abs(door.posX) {
                            // North or South wall
                            if door.posZ > 0 {
                                // South wall (Z > 0), door swings inward North (-Z)
                                let hingeX = door.posX < 0 ? (door.posX - door.width / 2.0) : (door.posX + door.width / 2.0)
                                pivotX = hingeX
                                pivotZ = door.posZ
                                if door.posX < 0 {
                                    startAngle = 0.0
                                    sweepAngle = -Float.pi / 2.0
                                } else {
                                    startAngle = Float.pi
                                    sweepAngle = Float.pi / 2.0
                                }
                            } else {
                                // North wall (Z < 0), door swings inward South (+Z)
                                let hingeX = door.posX < 0 ? (door.posX - door.width / 2.0) : (door.posX + door.width / 2.0)
                                pivotX = hingeX
                                pivotZ = door.posZ
                                if door.posX < 0 {
                                    startAngle = 0.0
                                    sweepAngle = Float.pi / 2.0
                                } else {
                                    startAngle = Float.pi
                                    sweepAngle = -Float.pi / 2.0
                                }
                            }
                        } else {
                            // East or West wall
                            if door.posX > 0 {
                                // East wall (X > 0), swings inward West (-X)
                                pivotX = door.posX
                                pivotZ = door.posZ < 0 ? (door.posZ - door.width / 2.0) : (door.posZ + door.width / 2.0)
                                startAngle = Float.pi / 2.0
                                sweepAngle = Float.pi / 2.0
                            } else {
                                // West wall (X < 0), swings inward East (+X)
                                pivotX = door.posX
                                pivotZ = door.posZ < 0 ? (door.posZ - door.width / 2.0) : (door.posZ + door.width / 2.0)
                                startAngle = Float.pi / 2.0
                                sweepAngle = -Float.pi / 2.0
                            }
                        }
                    } else {
                        // Fallback when doors array not supplied
                        pivotX = box.centerX
                        pivotZ = box.maxZ
                        startAngle = 0.0
                        sweepAngle = -Float.pi / 2.0
                    }
                }

                return ViolationMarker(
                    id: "\(violation.id)-\(item.id)",
                    ruleId: violation.ruleId,
                    title: violation.ruleTitle,
                    severity: violation.severity,
                    measuredCm: violation.measuredClearanceCm,
                    requiredCm: violation.requiredClearanceCm,
                    centerX: box.centerX,
                    centerZ: box.centerZ,
                    sizeX: box.width,
                    sizeZ: box.length,
                    clearanceRadius: radius,
                    isDoorSwing: isDoor,
                    doorPivotX: pivotX,
                    doorPivotZ: pivotZ,
                    doorSwingRadius: swingRad,
                    doorStartAngle: startAngle,
                    doorSweepAngle: sweepAngle
                )
            }
        }
    }

    public func clearViolations() {
        violationMarkers.removeAll()
    }

    public func highlightFurniture(ids: Set<UUID>) {
        highlightedFurnitureIDs = ids
    }

    public func clearHighlights() {
        highlightedFurnitureIDs.removeAll()
    }

    public func isHighlighted(_ id: UUID) -> Bool {
        highlightedFurnitureIDs.contains(id)
    }

    public func toggleHighlight(for id: UUID) {
        if highlightedFurnitureIDs.contains(id) {
            highlightedFurnitureIDs.remove(id)
        } else {
            highlightedFurnitureIDs.insert(id)
        }
    }
}
