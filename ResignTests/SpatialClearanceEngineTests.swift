//
//  SpatialClearanceEngineTests.swift
//  ResignTests
//

import Testing
import Foundation
import simd
@testable import Resign

@Suite("Spatial Clearance Engine Tests")
struct SpatialClearanceEngineTests {

    let engine = SpatialClearanceEngine()

    @Test @MainActor func walkwayCriticalAndRecommendedViolations() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let layout = Layout(name: "Test Walkway")

        // Two pieces of furniture placed very close: distance between them is 50 cm (< 76.2 cm critical R1)
        let sofa = Furniture(
            name: "Sofa",
            category: "sofa",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            length: 1.0,
            width: 2.0,
            height: 0.8
        )
        let coffeeTable = Furniture(
            name: "Coffee Table",
            category: "table",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 1.0,
            length: 0.5,
            width: 1.2,
            height: 0.4
        )
        let bed = Furniture(
            name: "Bed",
            category: "bed",
            positionX: -1.5,
            positionY: 0.0,
            positionZ: -1.0,
            length: 2.0,
            width: 1.6,
            height: 1.0
        )
        let desk = Furniture(
            name: "Desk",
            category: "desk",
            positionX: 0.45,
            positionY: 0.0,
            positionZ: -1.0,
            length: 0.8,
            width: 0.6,
            height: 0.75
        )

        layout.furnitures = [sofa, coffeeTable, bed, desk]

        let violations = engine.checkWalkwayClearances(furnitures: layout.furnitures, roomLength: room.length, roomWidth: room.width)

        let r1Violations = violations.filter { $0.ruleId == PaneroZelnikRule.walkwayCritical }
        let r2Violations = violations.filter { $0.ruleId == PaneroZelnikRule.walkwayRecommended }

        #expect(!r1Violations.isEmpty, "Should detect critical walkway violation under 76.2 cm")
        #expect(!r2Violations.isEmpty, "Should detect recommended walkway warning between 76.2 cm and 91.4 cm")
    }

    @Test @MainActor func deskRearClearanceViolation() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let layout = Layout(name: "Test Desk Clearance")

        let desk = Furniture(
            name: "Work Desk",
            category: "desk",
            positionX: 1.0,
            positionY: 0.0,
            positionZ: -1.5,
            length: 0.7,
            width: 1.2,
            height: 0.75
        )
        let chair = Furniture(
            name: "Office Chair",
            category: "chair",
            positionX: 1.0,
            positionY: 0.0,
            positionZ: -1.0,
            length: 0.5,
            width: 0.5,
            height: 0.9
        )
        let bookshelf = Furniture(
            name: "Bookshelf",
            category: "bookshelf",
            positionX: 1.0,
            positionY: 0.0,
            positionZ: -0.4,
            length: 0.4,
            width: 1.0,
            height: 1.8
        )

        layout.furnitures = [desk, chair, bookshelf]
        let violations = engine.checkDeskClearance(furnitures: layout.furnitures, roomLength: room.length, roomWidth: room.width)

        let r3Violations = violations.filter { $0.ruleId == PaneroZelnikRule.deskRearClearance }
        #expect(!r3Violations.isEmpty, "Should detect desk rear pullback clearance under 76.2 cm")
        #expect(r3Violations[0].measuredClearanceCm < 76.2)
    }

    @Test @MainActor func bedOperationalZoneViolation() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let layout = Layout(name: "Test Bed Clearance")

        let bed = Furniture(
            name: "Queen Bed",
            category: "bed",
            positionX: -1.5,
            positionY: 0.0,
            positionZ: -0.5,
            length: 2.0,
            width: 1.6,
            height: 1.0
        )
        layout.furnitures = [bed]

        let violations = engine.checkBedClearance(furnitures: layout.furnitures, roomLength: room.length, roomWidth: room.width)
        let r4Violations = violations.filter { $0.ruleId == PaneroZelnikRule.bedOperationalZone }

        #expect(!r4Violations.isEmpty, "Should detect bed operational making clearance under 66 cm")
        #expect(r4Violations[0].measuredClearanceCm < 66.0)
    }

    @Test @MainActor func doorSwingObstructionViolation() {
        let layout = Layout(name: "Test Door Swing")
        let door = RoomOpening(type: "door", posX: -1.5, posY: 0.0, posZ: 2.1, width: 0.9, height: 2.1)

        let chair = Furniture(
            name: "Accent Chair",
            category: "chair",
            positionX: -1.5,
            positionY: 0.0,
            positionZ: 1.6,
            length: 0.6,
            width: 0.6,
            height: 0.8
        )
        layout.furnitures = [chair]

        let violations = engine.checkDoorSwing(furnitures: layout.furnitures, doors: [door])
        let r6Violations = violations.filter { $0.ruleId == PaneroZelnikRule.doorSwingUnobstructed }

        #expect(!r6Violations.isEmpty, "Should detect door swing obstruction (R6)")
        #expect(r6Violations[0].itemIds.contains(chair.id))
        #expect(r6Violations[0].severity == .critical)
    }

    @Test @MainActor func studio3DViewModelViolationRadiusCalculation() {
        let layout = Layout(name: "Test Markers")
        let desk = Furniture(
            name: "Workstation",
            category: "desk",
            positionX: 0.5,
            positionY: 0.0,
            positionZ: -1.0,
            length: 0.7,
            width: 1.2,
            height: 0.75
        )
        layout.furnitures = [desk]

        let violation = SpatialViolation(
            ruleId: PaneroZelnikRule.deskRearClearance,
            ruleTitle: "Desk rear egress",
            severity: .warning,
            measuredClearanceCm: 45.0,
            requiredClearanceCm: 76.2,
            itemIds: [desk.id],
            message: "Chair egress is restricted."
        )

        let viewModel = Studio3DViewModel()
        viewModel.setViolations([violation], in: layout)

        #expect(viewModel.violationMarkers.count == 1)
        let marker = viewModel.violationMarkers[0]
        #expect(marker.ruleId == PaneroZelnikRule.deskRearClearance)
        #expect(marker.severity == .warning)
        #expect(marker.clearanceRadius >= 0.762, "Clearance radius must reflect required operational buffer in meters")
        #expect(marker.clearanceRadius > Float(max(desk.width, desk.length) * 0.5), "Radius must extend beyond furniture footprint")
    }

    @Test @MainActor func ruleSpecificDistinctColors() {
        let rules = [
            PaneroZelnikRule.walkwayCritical,
            PaneroZelnikRule.walkwayRecommended,
            PaneroZelnikRule.deskRearClearance,
            PaneroZelnikRule.bedOperationalZone,
            PaneroZelnikRule.bedStorageZone,
            PaneroZelnikRule.doorSwingUnobstructed
        ]

        var colorDescriptions = Set<String>()
        for rule in rules {
            let marker = ViolationMarker(
                id: "test-\(rule)",
                ruleId: rule,
                title: "Test",
                severity: .warning,
                measuredCm: 50.0,
                requiredCm: 80.0,
                centerX: 0.0,
                centerZ: 0.0,
                sizeX: 1.0,
                sizeZ: 1.0
            )
            let colorDesc = marker.uiColor.description
            #expect(!colorDescriptions.contains(colorDesc), "Each rule must have a distinct color theme")
            colorDescriptions.insert(colorDesc)
        }
        #expect(colorDescriptions.count == rules.count)
    }

    @Test @MainActor func contextualDoorSwingGeometryCalculation() {
        let layout = Layout(name: "Door Clash")
        let chair = Furniture(
            name: "Accent Chair",
            category: "chair",
            positionX: -1.5,
            positionY: 0.0,
            positionZ: 1.6,
            length: 0.6,
            width: 0.6,
            height: 0.8
        )
        layout.furnitures = [chair]

        let door = RoomOpening(type: "door", posX: -1.5, posY: 0.0, posZ: 2.1, width: 0.9, height: 2.1)

        let violation = SpatialViolation(
            ruleId: PaneroZelnikRule.doorSwingUnobstructed,
            ruleTitle: "Door Swing Obstructed",
            severity: .critical,
            measuredClearanceCm: 0.0,
            requiredClearanceCm: 90.0,
            itemIds: [chair.id],
            message: "Chair obstructs door swing."
        )

        let viewModel = Studio3DViewModel()
        viewModel.setViolations([violation], in: layout, doors: [door])

        #expect(viewModel.violationMarkers.count == 1)
        let marker = viewModel.violationMarkers[0]
        #expect(marker.isDoorSwing == true)
        #expect(marker.doorSwingRadius == 0.9)
        #expect(marker.doorPivotZ == 2.1)
        #expect(abs(marker.doorSweepAngle) == Float.pi / 2.0, "Door sweep angle must be a 90° arc")
    }

    // MARK: - 3D Studio Boundaries, Clamping & Rigid Collisions

    @Test func clampsPositionWithinRoomDrywallBoundariesAtZeroYaw() {
        // Room 5.0m wide (X: -2.5 to +2.5), 6.0m long (Z: -3.0 to +3.0)
        // Bed 1.6m wide, 2.0m long at yaw = 0 (half-extents: X = 0.8, Z = 1.0)
        // Max valid X is 2.5 - 0.8 = 1.7, min X is -1.7
        // Max valid Z is 3.0 - 1.0 = 2.0, min Z is -2.0

        let outsidePos = SIMD2<Float>(3.5, 4.0)
        let clamped = SpatialClearanceEngine.clampToRoomBoundaries(
            position: outsidePos,
            furnitureWidth: 1.6,
            furnitureLength: 2.0,
            rotationYaw: 0,
            roomWidth: 5.0,
            roomLength: 6.0
        )

        #expect(abs(clamped.x - 1.7) < 0.001)
        #expect(abs(clamped.y - 2.0) < 0.001)

        let negativeOutside = SIMD2<Float>(-3.0, -5.0)
        let clampedNegative = SpatialClearanceEngine.clampToRoomBoundaries(
            position: negativeOutside,
            furnitureWidth: 1.6,
            furnitureLength: 2.0,
            rotationYaw: 0,
            roomWidth: 5.0,
            roomLength: 6.0
        )

        #expect(abs(clampedNegative.x - (-1.7)) < 0.001)
        #expect(abs(clampedNegative.y - (-2.0)) < 0.001)
    }

    @Test func clampsPositionWithinRoomBoundariesAtNinetyDegreesYaw() {
        // Bed 1.6m wide, 2.0m long rotated 90° (yaw = pi/2):
        // Extent in X becomes length/2 = 1.0m, extent in Z becomes width/2 = 0.8m
        // Room 5.0m wide (X limit: 2.5 - 1.0 = 1.5), 6.0m long (Z limit: 3.0 - 0.8 = 2.2)

        let pos = SIMD2<Float>(2.0, 2.5)
        let clamped = SpatialClearanceEngine.clampToRoomBoundaries(
            position: pos,
            furnitureWidth: 1.6,
            furnitureLength: 2.0,
            rotationYaw: .pi / 2,
            roomWidth: 5.0,
            roomLength: 6.0
        )

        #expect(abs(clamped.x - 1.5) < 0.001)
        #expect(abs(clamped.y - 2.2) < 0.001)
    }

    @Test func clampsPositionWithinOffsetRoomBoundaries() {
        // Scanned room like Room-2 where floor/walls are shifted:
        // X spans [-3.30, +0.70] (center ~ -1.30m), Z spans [-2.40, +1.80] (center ~ -0.30m)
        // Bed 1.6m wide, 2.0m long at yaw = 0 (half-extents: X = 0.8, Z = 1.0)
        // Valid X: [-3.30 + 0.8, 0.70 - 0.8] = [-2.50, -0.10]
        // Valid Z: [-2.40 + 1.0, 1.80 - 1.0] = [-1.40, +0.80]

        let insidePos = SIMD2<Float>(-1.30, -0.30)
        let clampedInside = SpatialClearanceEngine.clampToRoomBoundaries(
            position: insidePos,
            furnitureWidth: 1.6,
            furnitureLength: 2.0,
            rotationYaw: 0,
            minX: -3.30,
            maxX: 0.70,
            minZ: -2.40,
            maxZ: 1.80
        )
        #expect(abs(clampedInside.x - (-1.30)) < 0.001)
        #expect(abs(clampedInside.y - (-0.30)) < 0.001)

        // Dragged outside south wall to Z = -3.0 -> must be clamped to south wall limit -1.40
        let southOutside = SIMD2<Float>(-1.30, -3.0)
        let clampedSouth = SpatialClearanceEngine.clampToRoomBoundaries(
            position: southOutside,
            furnitureWidth: 1.6,
            furnitureLength: 2.0,
            rotationYaw: 0,
            minX: -3.30,
            maxX: 0.70,
            minZ: -2.40,
            maxZ: 1.80
        )
        #expect(abs(clampedSouth.y - (-1.40)) < 0.001)

        // Dragged toward north wall to Z = +2.5 -> must be clamped to north wall limit +0.80
        let northOutside = SIMD2<Float>(-1.30, 2.5)
        let clampedNorth = SpatialClearanceEngine.clampToRoomBoundaries(
            position: northOutside,
            furnitureWidth: 1.6,
            furnitureLength: 2.0,
            rotationYaw: 0,
            minX: -3.30,
            maxX: 0.70,
            minZ: -2.40,
            maxZ: 1.80
        )
        #expect(abs(clampedNorth.y - 0.80) < 0.001)
    }

    @Test func preventsRigidFurnitureBoundingBoxCollision() {
        // Bed at (0, 0, 0) of size 1.6m x 0.9m x 2.0m (X, Y, Z)
        let bed = FurnitureCollisionProxy(
            id: UUID(),
            category: "bed",
            position: SIMD3<Float>(0, 0.45, 0),
            dimensions: SIMD3<Float>(1.6, 0.9, 2.0),
            rotationYaw: 0
        )

        // Wardrobe overlapping the bed at (0.5, 0, 0.5)
        let wardrobe = FurnitureCollisionProxy(
            id: UUID(),
            category: "storage",
            position: SIMD3<Float>(0.5, 1.0, 0.5),
            dimensions: SIMD3<Float>(1.0, 2.0, 0.6),
            rotationYaw: 0
        )

        let collides = SpatialClearanceEngine.checkCollision(itemA: bed, itemB: wardrobe)
        #expect(collides == true)

        // Wardrobe placed safely away at (2.0, 0, 0)
        let separatedWardrobe = FurnitureCollisionProxy(
            id: UUID(),
            category: "storage",
            position: SIMD3<Float>(2.0, 1.0, 0),
            dimensions: SIMD3<Float>(1.0, 2.0, 0.6),
            rotationYaw: 0
        )
        let separatedCollides = SpatialClearanceEngine.checkCollision(itemA: bed, itemB: separatedWardrobe)
        #expect(separatedCollides == false)
    }

    @Test func allowsChairToTuckUnderDeskUpToAllowance() {
        // Desk at (0, 0.375, 0), dimensions: 1.4m wide (X), 0.75m high (Y), 0.70m deep (Z)
        let desk = FurnitureCollisionProxy(
            id: UUID(),
            category: "desk",
            position: SIMD3<Float>(0, 0.375, 0),
            dimensions: SIMD3<Float>(1.4, 0.75, 0.70),
            rotationYaw: 0
        )

        // Chair at (0, 0.45, 0.45), dimensions: 0.6m wide (X), 0.9m high (Y), 0.6m deep (Z)
        // Front edge of chair reaches Z = 0.45 - 0.30 = 0.15 (partially tucked inside desk's back half Z: [-0.35, +0.35])
        // Overlap depth is 0.35 - 0.15 = 0.20m (~33% of chair depth, well under 65% limit)
        let tuckedChair = FurnitureCollisionProxy(
            id: UUID(),
            category: "chair",
            position: SIMD3<Float>(0, 0.45, 0.45),
            dimensions: SIMD3<Float>(0.6, 0.9, 0.6),
            rotationYaw: 0
        )

        let collides = SpatialClearanceEngine.checkCollision(itemA: desk, itemB: tuckedChair)
        // Tuck-in allowance permits natural chair placement under the desk!
        #expect(collides == false)
    }

    @Test func preventsChairFromPenetratingCompletelyThroughDesk() {
        let desk = FurnitureCollisionProxy(
            id: UUID(),
            category: "desk",
            position: SIMD3<Float>(0, 0.375, 0),
            dimensions: SIMD3<Float>(1.4, 0.75, 0.70),
            rotationYaw: 0
        )

        // Chair pushed all the way through the desk to center (Z = 0.0)
        let overTuckedChair = FurnitureCollisionProxy(
            id: UUID(),
            category: "chair",
            position: SIMD3<Float>(0, 0.45, 0.0),
            dimensions: SIMD3<Float>(0.6, 0.9, 0.6),
            rotationYaw: 0
        )

        let collides = SpatialClearanceEngine.checkCollision(itemA: desk, itemB: overTuckedChair)
        #expect(collides == true)
    }

    @Test func preventsTwoChairsFromColliding() {
        let chair1 = FurnitureCollisionProxy(
            id: UUID(),
            category: "chair",
            position: SIMD3<Float>(0, 0.45, 0),
            dimensions: SIMD3<Float>(0.6, 0.9, 0.6),
            rotationYaw: 0
        )

        let chair2 = FurnitureCollisionProxy(
            id: UUID(),
            category: "chair",
            position: SIMD3<Float>(0.2, 0.45, 0.1),
            dimensions: SIMD3<Float>(0.6, 0.9, 0.6),
            rotationYaw: 0
        )

        // Two chairs must never overlap/stack inside each other
        let collides = SpatialClearanceEngine.checkCollision(itemA: chair1, itemB: chair2)
        #expect(collides == true)
    }

    @Test func stepsRotationNinetyDegreesAroundYAxis() {
        let initialYaw: Float = 0.0
        let step1 = SpatialClearanceEngine.stepRotation90(currentYaw: initialYaw)
        #expect(abs(step1 - (.pi / 2.0)) < 0.001)

        let step2 = SpatialClearanceEngine.stepRotation90(currentYaw: step1)
        #expect(abs(step2 - .pi) < 0.001)

        let step3 = SpatialClearanceEngine.stepRotation90(currentYaw: step2)
        #expect(abs(step3 - (3.0 * .pi / 2.0)) < 0.001)

        let step4 = SpatialClearanceEngine.stepRotation90(currentYaw: step3)
        #expect(abs(step4 - 0.0) < 0.001)
    }

    @Test func snapsYawToNearestOrthogonalIncrementWhenWithinThreshold() {
        // Near 90° (pi/2 = 1.570796): 1.52 is within 0.12 threshold -> snaps to pi/2
        let snapNear90 = SpatialClearanceEngine.snapYaw(rawYaw: 1.52, step: .pi / 2.0, threshold: 0.12)
        #expect(snapNear90.didSnap == true)
        #expect(abs(snapNear90.yaw - (.pi / 2.0)) < 0.001)

        // Near 0° (or 2pi): 0.05 is within threshold -> snaps to 0.0
        let snapNear0 = SpatialClearanceEngine.snapYaw(rawYaw: 0.05, step: .pi / 2.0, threshold: 0.12)
        #expect(snapNear0.didSnap == true)
        #expect(abs(snapNear0.yaw - 0.0) < 0.001)

        // Intermediate angle: 0.80 rad (~45.8°) is beyond 0.12 threshold of 0° and 90° -> does not snap
        let noSnap = SpatialClearanceEngine.snapYaw(rawYaw: 0.80, step: .pi / 2.0, threshold: 0.12)
        #expect(noSnap.didSnap == false)
        #expect(abs(noSnap.yaw - 0.80) < 0.001)
    }

    @Test func verticalStackingAllowsTVOnTopOfConsoleAndBlocksTallWardrobeCollisions() {
        // Media console resting on floor (positionY = 0.0, height = 0.50 -> spans [0.0, 0.50])
        let console = FurnitureCollisionProxy(
            id: UUID(),
            category: "closet",
            position: SIMD3<Float>(0, 0.0, 0),
            dimensions: SIMD3<Float>(1.4, 0.50, 0.45),
            rotationYaw: 0
        )

        // Television resting directly on top of console (positionY = 0.50, height = 0.65 -> spans [0.50, 1.15])
        let tvOnConsole = FurnitureCollisionProxy(
            id: UUID(),
            category: "television",
            position: SIMD3<Float>(0, 0.50, 0),
            dimensions: SIMD3<Float>(1.2, 0.65, 0.15),
            rotationYaw: 0
        )

        #expect(SpatialClearanceEngine.checkCollision(itemA: console, itemB: tvOnConsole) == false)

        // Tall wardrobe resting on floor (positionY = 0.0, height = 2.0 -> spans [0.0, 2.0])
        let wardrobe = FurnitureCollisionProxy(
            id: UUID(),
            category: "closet",
            position: SIMD3<Float>(0, 0.0, 0),
            dimensions: SIMD3<Float>(1.2, 2.0, 0.60),
            rotationYaw: 0
        )

        // Wall shelf mounted at Y = 1.35m (spans [1.35, 1.70]), overlapping upper half of wardrobe
        let wallShelf = FurnitureCollisionProxy(
            id: UUID(),
            category: "closet",
            position: SIMD3<Float>(0, 1.35, 0),
            dimensions: SIMD3<Float>(1.0, 0.35, 0.35),
            rotationYaw: 0
        )

        #expect(SpatialClearanceEngine.checkCollision(itemA: wardrobe, itemB: wallShelf) == true)
    }

    @Test func polygonClampingBridgesDoorwayGapsAndIgnoresOpenWallFragments() {
        // L-shaped room where the East wall has a 0.80m doorway gap from Z = -1.2 to Z = -0.4
        let wallsWithDoorGap: [RoomPlanSnapshot.WallSegment] = [
            .init(startX: -2.0, startZ: -2.0, endX: 3.0, endZ: -2.0),
            .init(startX: 3.0, startZ: -2.0, endX: 3.0, endZ: -1.2), // Doorway gap [-1.2, -0.4]
            .init(startX: 3.0, startZ: -0.4, endX: 3.0, endZ: 0.0),
            .init(startX: 3.0, startZ: 0.0, endX: 0.0, endZ: 0.0),
            .init(startX: 0.0, startZ: 0.0, endX: 0.0, endZ: 2.0),
            .init(startX: 0.0, startZ: 2.0, endX: -2.0, endZ: 2.0),
            .init(startX: -2.0, startZ: 2.0, endX: -2.0, endZ: -2.0)
        ]

        // Interior point at (1.5, -0.8) directly aligned with the doorway gap at Z = -0.8
        // Without gap bridging, a +X ray passes through the doorway gap and falsely reports outside!
        let interiorAlignedWithDoor = SIMD2<Float>(1.5, -0.8)
        #expect(SpatialClearanceEngine.isPointInsidePolygon(interiorAlignedWithDoor, walls: wallsWithDoorGap) == true)

        let clampedInside = SpatialClearanceEngine.clampToRoomBoundaries(
            position: interiorAlignedWithDoor,
            furnitureWidth: 0.6,
            furnitureLength: 0.6,
            rotationYaw: 0,
            minX: -2.0,
            maxX: 3.0,
            minZ: -2.0,
            maxZ: 2.0,
            walls: wallsWithDoorGap
        )
        #expect(simd_distance(clampedInside, interiorAlignedWithDoor) < 0.01)

        // Incomplete scan with only 2 disconnected wall segments must fallback to bounding box without teleporting
        let openFragments: [RoomPlanSnapshot.WallSegment] = [
            .init(startX: -2.0, startZ: -2.0, endX: 2.0, endZ: -2.0),
            .init(startX: -2.0, startZ: 2.0, endX: 2.0, endZ: 2.0)
        ]
        let centerPoint = SIMD2<Float>(0.5, 0.5)
        let clampedOpen = SpatialClearanceEngine.clampToRoomBoundaries(
            position: centerPoint,
            furnitureWidth: 0.6,
            furnitureLength: 0.6,
            rotationYaw: 0,
            minX: -2.0,
            maxX: 2.0,
            minZ: -2.0,
            maxZ: 2.0,
            walls: openFragments
        )
        #expect(simd_distance(clampedOpen, centerPoint) < 0.01)
    }
}
