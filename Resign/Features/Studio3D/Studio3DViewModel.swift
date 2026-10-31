import Observation
import SwiftData
import simd
import Foundation

/// Holds the confirmed lighting, the draft being edited in the sheet,
/// and the interactive 3D furniture selection and rearrangement state.
@Observable
@MainActor
public final class Studio3DViewModel {
    private(set) var lightingSettings = LightingSimulationSettings()
    var lightingDraft = LightingSimulationSettings()
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

    func beginLightingEditing() {
        lightingDraft = lightingSettings
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
}
