//
//  RoomCaptureSanitizerTests.swift
//  ResignTests
//

import Foundation
import Testing
import simd
import SwiftData
import RealityKit
@testable import Resign

@Suite("RoomPlan Capture Sanitizer & Mapper Tests")
struct RoomCaptureSanitizerTests {

    @Test func floorGroundingClampsFloatingYPositionToZero() {
        let sanitizer = RoomCaptureSanitizer()

        let floatingBed = ScannedObjectPayload(
            rawCategory: "bed",
            position: SIMD3<Float>(1.2, 0.08, -1.5), // Y is floating 8 cm
            dimensions: SIMD3<Float>(1.6, 1.0, 2.0),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [floatingBed],
            roomWidth: 5.0,
            roomLength: 4.2
        )

        #expect(sanitized.count == 1)
        #expect(sanitized[0].position.y == 0.0)
        #expect(sanitized[0].position.x == 1.2)
        #expect(sanitized[0].position.z == -1.5)
    }

    @Test func bathroomAndApplianceDetectionsAreDiscarded() {
        let sanitizer = RoomCaptureSanitizer()

        let falseBathtub = ScannedObjectPayload(
            rawCategory: "bathtub",
            position: SIMD3<Float>(0, 0, 0),
            dimensions: SIMD3<Float>(1.5, 0.6, 0.8),
            rotationYaw: 0
        )
        let falseToilet = ScannedObjectPayload(
            rawCategory: "toilet",
            position: SIMD3<Float>(1.0, 0, 1.0),
            dimensions: SIMD3<Float>(0.5, 0.7, 0.6),
            rotationYaw: 0
        )
        let falseSink = ScannedObjectPayload(
            rawCategory: "sink",
            position: SIMD3<Float>(-1.0, 0, -1.0),
            dimensions: SIMD3<Float>(0.6, 0.8, 0.5),
            rotationYaw: 0
        )
        let falseRefrigerator = ScannedObjectPayload(
            rawCategory: "refrigerator",
            position: SIMD3<Float>(2.0, 0, 0),
            dimensions: SIMD3<Float>(0.9, 1.8, 0.8),
            rotationYaw: 0
        )
        let validBed = ScannedObjectPayload(
            rawCategory: "bed",
            position: SIMD3<Float>(-1.2, 0, 0),
            dimensions: SIMD3<Float>(1.6, 1.0, 2.0),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [falseBathtub, falseToilet, falseSink, falseRefrigerator, validBed],
            roomWidth: 5.0,
            roomLength: 4.2
        )

        #expect(sanitized.count == 1)
        #expect(sanitized[0].category == "bed")
    }

    @Test func homeownerLivingCategoriesAreWhitelistedAndMapped() {
        let sanitizer = RoomCaptureSanitizer()

        let objects = [
            ScannedObjectPayload(rawCategory: "bed", position: .zero, dimensions: [1.6, 1.0, 2.0], rotationYaw: 0),
            ScannedObjectPayload(rawCategory: "sofa", position: .zero, dimensions: [2.1, 0.85, 0.95], rotationYaw: 0),
            ScannedObjectPayload(rawCategory: "chair", position: .zero, dimensions: [0.65, 0.85, 0.65], rotationYaw: 0),
            ScannedObjectPayload(rawCategory: "storage", position: .zero, dimensions: [1.2, 2.0, 0.6], rotationYaw: 0),
            ScannedObjectPayload(rawCategory: "television", position: .zero, dimensions: [1.3, 1.1, 0.4], rotationYaw: 0),
            ScannedObjectPayload(rawCategory: "fireplace", position: .zero, dimensions: [1.2, 1.0, 0.5], rotationYaw: 0),
        ]

        let sanitized = sanitizer.sanitize(
            objects: objects,
            roomWidth: 6.0,
            roomLength: 6.0
        )

        let categories = sanitized.map(\.category)
        #expect(categories == ["bed", "sofa", "chair", "closet", "television", "fireplace"])
    }

    @Test func tableCategorizationDistinguishesWorkDeskFromDiningTable() {
        let sanitizer = RoomCaptureSanitizer()

        // Desk dimensions (height ~0.75m, width ~1.2m, length ~0.65m)
        let deskObject = ScannedObjectPayload(
            rawCategory: "table",
            position: .zero,
            dimensions: SIMD3<Float>(1.2, 0.74, 0.65),
            rotationYaw: 0
        )

        // Dining table dimensions (width ~1.8m, length ~1.0m, height ~0.76m)
        let diningTableObject = ScannedObjectPayload(
            rawCategory: "table",
            position: .zero,
            dimensions: SIMD3<Float>(1.8, 0.76, 1.0),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [deskObject, diningTableObject],
            roomWidth: 5.0,
            roomLength: 5.0
        )

        #expect(sanitized.count == 2)
        #expect(sanitized[0].category == "desk")
        #expect(sanitized[1].category == "table")
    }

    @Test func uniformScaleMultiplierMatchesWidthRatio() {
        let sanitizer = RoomCaptureSanitizer()

        // Detected twin bed (1.0m width) vs Queen master model (1.6m width)
        let twinBed = ScannedObjectPayload(
            rawCategory: "bed",
            position: .zero,
            dimensions: SIMD3<Float>(1.0, 0.9, 1.9),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [twinBed],
            roomWidth: 4.0,
            roomLength: 4.0
        )

        #expect(sanitized.count == 1)
        let expectedScale = Float(1.0 / 1.6)
        #expect(abs(sanitized[0].uniformScale - expectedScale) < 0.001)
    }

    @Test @MainActor func mapperAssemblesCompleteSwiftDataGraph() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let payload = CapturedRoomPayload(
            roomLength: 4.2,
            roomWidth: 5.0,
            roomHeight: 2.6,
            openings: [
                ScannedOpeningPayload(type: "window", position: [2.5, 1.45, 0.0], dimensions: [1.6, 1.2, 0.1]),
                ScannedOpeningPayload(type: "door", position: [0.0, 1.05, -2.1], dimensions: [0.9, 2.1, 0.1])
            ],
            objects: [
                ScannedObjectPayload(rawCategory: "bed", position: [-1.3, 0.05, -1.0], dimensions: [1.6, 1.0, 2.0], rotationYaw: 0),
                ScannedObjectPayload(rawCategory: "table", position: [1.8, 0.0, -1.2], dimensions: [1.2, 0.75, 0.65], rotationYaw: .pi / 2),
                ScannedObjectPayload(rawCategory: "bathtub", position: [0, 0, 0], dimensions: [1.5, 0.6, 0.8], rotationYaw: 0) // Should be discarded
            ]
        )

        let mapper = RoomCaptureMapper()
        let room = mapper.mapToRoom(payload: payload, roomName: "Guest Bedroom")
        context.insert(room)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Room>())
        #expect(fetched.count == 1)

        let savedRoom = fetched[0]
        #expect(savedRoom.name == "Guest Bedroom")
        #expect(savedRoom.length == 5.0)
        #expect(savedRoom.width == 4.2)
        #expect(savedRoom.height == 2.6)

        // Verify openings
        #expect(savedRoom.openings.count == 2)
        let types = Set(savedRoom.openings.map(\.type))
        #expect(types.contains("window"))
        #expect(types.contains("door"))

        // Verify layout & furniture
        #expect(savedRoom.layouts.count == 1)
        let layout = savedRoom.layouts[0]
        #expect(layout.name == "Original Scan")
        #expect(layout.furnitures.count == 2) // Bed and Desk (bathtub discarded)

        let furnitureCategories = Set(layout.furnitures.map(\.category))
        #expect(furnitureCategories.contains("bed"))
        #expect(furnitureCategories.contains("desk"))

        // Verify all furniture is grounded at Y = 0.0
        for item in layout.furnitures {
            #expect(item.positionY == 0.0)
        }
    }

    @Test func snapsDeskToAngledWallSegmentWithinThreshold() {
        let sanitizer = RoomCaptureSanitizer()

        // 45 degree wall segment running from (0, 0) to (2, 2)
        let wall = ScannedWallPayload(
            position: SIMD3<Float>(1.0, 1.3, 1.0),
            dimensions: SIMD3<Float>(2.828, 2.6, 0.1),
            rotationYaw: .pi / 4
        )

        // Desk near the wall (gap ~ 8cm, well within 15cm threshold)
        let desk = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(1.0, 0.0, 1.0),
            dimensions: SIMD3<Float>(1.2, 0.75, 0.7),
            rotationYaw: .pi / 4
        )

        let sanitized = sanitizer.sanitize(
            objects: [desk],
            roomWidth: 6.0,
            roomLength: 6.0,
            walls: [wall]
        )

        #expect(sanitized.count == 1)
        #expect(sanitized[0].category == "desk")
        #expect(sanitized[0].position.y == 0.0)
        #expect(abs(sanitized[0].rotationYaw - (.pi / 4)) < 0.01)
    }

    @Test func snappingToWallFactorsInWallThicknessWithZeroDrywallPenetration() {
        let sanitizer = RoomCaptureSanitizer()

        // South wall running along X at Z = 2.0m, wall thickness = 0.10m
        // Inner plaster surface is at Z = 2.0 - 0.05 = 1.95m
        let wall = ScannedWallPayload(
            position: SIMD3<Float>(0, 1.3, 2.0),
            dimensions: SIMD3<Float>(4.0, 2.6, 0.10),
            rotationYaw: 0
        )

        // Desk placed near the wall: width = 1.2m, depth = 0.60m (dimensions.z)
        // Center at Z = 1.68m (within 15cm snap threshold)
        let desk = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(0, 0, 1.68),
            dimensions: SIMD3<Float>(1.2, 0.75, 0.60),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [desk],
            roomWidth: 5.0,
            roomLength: 4.0,
            walls: [wall]
        )

        #expect(sanitized.count == 1)
        // Plaster face is at 1.95m. Desk half-depth is 0.30m.
        // True desk center must sit at 1.95 - 0.30 = 1.65m (NOT 1.70m, which would penetrate 5cm into plaster)
        #expect(abs(sanitized[0].position.z - 1.65) < 0.01)
        // Back edge of desk must sit precisely on the plaster face (1.65 + 0.30 = 1.95m)
        let backEdgeZ = sanitized[0].position.z + (desk.dimensions.z / 2.0)
        #expect(abs(backEdgeZ - 1.95) < 0.01)
    }

    @Test func perpendicularObjectSnapsToPerpendicularAngle() {
        let sanitizer = RoomCaptureSanitizer()

        // Wall with yaw = 0 (runs along X)
        let wall = ScannedWallPayload(
            position: SIMD3<Float>(0, 1.3, -2.0),
            dimensions: SIMD3<Float>(4.0, 2.6, 0.10),
            rotationYaw: 0
        )

        // Bed placed perpendicular to wall (yaw = pi/2)
        let bed = ScannedObjectPayload(
            rawCategory: "bed",
            position: SIMD3<Float>(0, 0, -1.0),
            dimensions: SIMD3<Float>(1.6, 1.0, 2.0),
            rotationYaw: .pi / 2
        )

        let sanitized = sanitizer.sanitize(
            objects: [bed],
            roomWidth: 5.0,
            roomLength: 4.0,
            walls: [wall]
        )

        #expect(sanitized.count == 1)
        // Must preserve perpendicular orientation (pi / 2), NOT forcefully spin parallel (0)
        #expect(abs(sanitized[0].rotationYaw - (.pi / 2)) < 0.01)
    }

    @Test func classifiesFurnitureIntoDiscreteArchetypeNames() {
        let sanitizer = RoomCaptureSanitizer()

        let twinBed = ScannedObjectPayload(rawCategory: "bed", position: [0, 0, 0], dimensions: [1.0, 0.9, 2.0], rotationYaw: 0)
        let queenBed = ScannedObjectPayload(rawCategory: "bed", position: [0, 0, 0], dimensions: [1.6, 0.9, 2.0], rotationYaw: 0)
        let kingBed = ScannedObjectPayload(rawCategory: "bed", position: [0, 0, 0], dimensions: [1.9, 0.9, 2.0], rotationYaw: 0)
        let compactDesk = ScannedObjectPayload(rawCategory: "table", position: [0, 0, 0], dimensions: [1.1, 0.75, 0.6], rotationYaw: 0)
        let workDesk = ScannedObjectPayload(rawCategory: "table", position: [0, 0, 0], dimensions: [1.6, 0.75, 0.8], rotationYaw: 0)
        let loveseat = ScannedObjectPayload(rawCategory: "sofa", position: [0, 0, 0], dimensions: [1.5, 0.85, 0.9], rotationYaw: 0)
        let sofa = ScannedObjectPayload(rawCategory: "sofa", position: [0, 0, 0], dimensions: [2.2, 0.85, 0.9], rotationYaw: 0)

        let sanitized = sanitizer.sanitize(
            objects: [twinBed, queenBed, kingBed, compactDesk, workDesk, loveseat, sofa],
            roomWidth: 8.0,
            roomLength: 8.0
        )

        #expect(sanitized[0].name == "Twin Bed")
        #expect(sanitized[1].name == "Queen Bed")
        #expect(sanitized[2].name == "King Bed")
        #expect(sanitized[3].name == "Compact Desk")
        #expect(sanitized[4].name == "Work Desk")
        #expect(sanitized[5].name == "2-Seat Sofa")
        #expect(sanitized[6].name == "3-Seat Sofa")
    }

    @Test func floorGroundingClampsToCapturedFloorLevel() {
        let sanitizer = RoomCaptureSanitizer()

        let floatingBed = ScannedObjectPayload(
            rawCategory: "bed",
            position: SIMD3<Float>(1.2, -1.35, -1.5),
            dimensions: SIMD3<Float>(1.6, 1.0, 2.0),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [floatingBed],
            roomWidth: 5.0,
            roomLength: 4.2,
            floorLevel: -1.69
        )

        #expect(sanitized.count == 1)
        #expect(abs(sanitized[0].position.y - (-1.69)) < 0.001)
    }

    @Test func mapperNormalizesFurnitureYToFloorZeroInLayout() {
        let mapper = RoomCaptureMapper()

        let payload = CapturedRoomPayload(
            roomLength: 4.2,
            roomWidth: 5.0,
            roomHeight: 2.6,
            floorLevel: -1.69,
            openings: [],
            objects: [
                ScannedObjectPayload(
                    rawCategory: "bed",
                    position: SIMD3<Float>(1.0, -1.2, -1.0),
                    dimensions: SIMD3<Float>(1.6, 1.0, 2.0),
                    rotationYaw: 0
                )
            ]
        )

        let room = mapper.mapToRoom(payload: payload)
        let layout = room.layouts.first
        #expect(layout != nil)
        #expect(layout?.furnitures.count == 1)
        // ADR 0029 invariant: persistent furniture must be grounded at floor Y = 0.0, NOT negative raw floorLevel (-1.69)
        #expect(layout?.furnitures.first?.positionY == 0.0)
    }

    @Test func standingTelevisionRestsFlushOnTopOfMediaConsoleAndAlignsYaw() {
        let sanitizer = RoomCaptureSanitizer()
        let floorLevel: Float = -1.6906

        // East wall running along Z (yaw = pi / 2) at X = 1.72m
        let eastWall = ScannedWallPayload(
            position: SIMD3<Float>(1.72, -0.09, 0.0),
            dimensions: SIMD3<Float>(4.06, 3.21, 0.10),
            rotationYaw: .pi / 2
        )

        // Floor-standing media console (storage -> closet, height = 0.845m)
        let console = ScannedObjectPayload(
            rawCategory: "storage",
            position: SIMD3<Float>(1.408, -1.268, 0.233),
            dimensions: SIMD3<Float>(1.713, 0.845, 0.572),
            rotationYaw: .pi / 2
        )

        // Standing TV resting on top of the console with 5° scanning yaw jitter
        let standingTV = ScannedObjectPayload(
            rawCategory: "television",
            position: SIMD3<Float>(1.394, -0.570, 0.113),
            dimensions: SIMD3<Float>(1.097, 0.683, 0.080),
            rotationYaw: (.pi / 2) - 0.087
        )

        let sanitized = sanitizer.sanitize(
            objects: [console, standingTV],
            roomWidth: 4.23,
            roomLength: 4.06,
            walls: [eastWall],
            floorLevel: floorLevel
        )

        #expect(sanitized.count == 2)

        let sanitizedConsole = sanitized[0]
        #expect(sanitizedConsole.category == "closet")
        #expect(sanitizedConsole.name == "Media Console")
        #expect(abs(sanitizedConsole.position.y - floorLevel) < 0.001)

        let sanitizedTV = sanitized[1]
        #expect(sanitizedTV.category == "television")
        #expect(sanitizedTV.name == "Television")
        // TV base must sit flush on top of the console (floorLevel + 0.845), NOT on the floor
        let expectedTVBaseY = floorLevel + console.dimensions.y
        #expect(abs(sanitizedTV.position.y - expectedTVBaseY) < 0.001)
        // TV must remain centered on the console horizontally rather than yanked into the drywall
        #expect(abs(sanitizedTV.position.x - standingTV.position.x) < 0.001)
        // TV yaw jitter must still snap parallel to the East wall (pi / 2)
        #expect(abs(sanitizedTV.rotationYaw - (.pi / 2)) < 0.001)
    }

    @Test func wallMountedTelevisionAndFloatingShelfPreserveElevatedHeight() {
        let sanitizer = RoomCaptureSanitizer()
        let floorLevel: Float = -1.6906

        // Floating wall shelf mounted 1.52m above the floor
        let floatingShelf = ScannedObjectPayload(
            rawCategory: "storage",
            position: SIMD3<Float>(-1.73, 0.049, -1.21),
            dimensions: SIMD3<Float>(0.65, 0.44, 0.31),
            rotationYaw: 0
        )

        // Wall-mounted TV with no console underneath
        let wallTV = ScannedObjectPayload(
            rawCategory: "television",
            position: SIMD3<Float>(0.0, -0.40, 1.85),
            dimensions: SIMD3<Float>(1.30, 0.74, 0.07),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [floatingShelf, wallTV],
            roomWidth: 4.23,
            roomLength: 4.06,
            floorLevel: floorLevel
        )

        #expect(sanitized.count == 2)

        // Floating shelf preserves its elevated bottom Y (0.049 - 0.22 = -0.171) and is named "Wall Shelf"
        #expect(sanitized[0].name == "Wall Shelf")
        #expect(abs(sanitized[0].position.y - (-0.171)) < 0.005)
        #expect(sanitized[0].position.y > floorLevel + 1.0)

        // Wall-mounted TV preserves its elevated bottom Y (-0.40 - 0.37 = -0.77)
        #expect(sanitized[1].name == "Television")
        #expect(abs(sanitized[1].position.y - (-0.77)) < 0.005)
        #expect(sanitized[1].position.y > floorLevel + 0.5)
    }

    @Test func orthogonalYawSnappingEliminatesMicroRotationalJitterAgainstWall() {
        let sanitizer = RoomCaptureSanitizer()

        // North wall along X at Z = -2.0m, thickness = 0.10m (inner plaster face at Z = -1.95m)
        let northWall = ScannedWallPayload(
            position: SIMD3<Float>(0, 1.3, -2.0),
            dimensions: SIMD3<Float>(4.0, 2.6, 0.10),
            rotationYaw: 0
        )

        // Desk placed against North wall with 8 degrees (0.14 rad) of rotational scanning jitter
        let jitteredDesk = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(0.5, 0.0, -1.62),
            dimensions: SIMD3<Float>(1.40, 0.75, 0.60),
            rotationYaw: 0.14
        )

        let sanitized = sanitizer.sanitize(
            objects: [jitteredDesk],
            roomWidth: 4.0,
            roomLength: 4.0,
            walls: [northWall]
        )

        #expect(sanitized.count == 1)
        // Yaw must snap cleanly to 0.0 rad
        #expect(abs(sanitized[0].rotationYaw - 0.0) < 0.001)
        // Using orthogonalized depth (0.60 / 2 = 0.30m), center Z must sit at -1.95 + 0.30 = -1.65m
        #expect(abs(sanitized[0].position.z - (-1.65)) < 0.005)
    }

    @Test func freeFloatingLivingRoomFurnitureNeverSnapsPositionIntoWall() {
        let sanitizer = RoomCaptureSanitizer()

        // North wall at Z = -2.0m, thickness = 0.10m (inner plaster face at Z = -1.95m)
        let northWall = ScannedWallPayload(
            position: SIMD3<Float>(0, 1.3, -2.0),
            dimensions: SIMD3<Float>(5.0, 2.6, 0.10),
            rotationYaw: 0
        )

        // Floating sofa 5cm away from inner plaster face (center at Z = -1.45m, depth = 0.90m -> back at -1.90m)
        let floatingSofa = ScannedObjectPayload(
            rawCategory: "sofa",
            position: SIMD3<Float>(-1.0, 0.0, -1.45),
            dimensions: SIMD3<Float>(2.0, 0.85, 0.90),
            rotationYaw: 0.05
        )

        // Floating accent chair 4cm from inner plaster face
        let floatingChair = ScannedObjectPayload(
            rawCategory: "chair",
            position: SIMD3<Float>(1.2, 0.0, -1.59),
            dimensions: SIMD3<Float>(0.65, 0.85, 0.64),
            rotationYaw: 0.35
        )

        // Wardrobe 5cm from inner plaster face (should snap flush to Z = -1.95 + 0.30 = -1.65m)
        let wallWardrobe = ScannedObjectPayload(
            rawCategory: "storage",
            position: SIMD3<Float>(0.0, 0.0, -1.60),
            dimensions: SIMD3<Float>(1.20, 2.00, 0.60),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [floatingSofa, floatingChair, wallWardrobe],
            roomWidth: 5.0,
            roomLength: 4.0,
            walls: [northWall]
        )

        #expect(sanitized.count == 3)
        // Sofa and Chair must NOT have their Z position pulled into the wall
        #expect(abs(sanitized[0].position.z - (-1.45)) < 0.001)
        #expect(abs(sanitized[1].position.z - (-1.59)) < 0.001)
        // Wardrobe IS wall-anchored and within 8cm threshold, so it snaps flush to -1.65m
        #expect(abs(sanitized[2].position.z - (-1.65)) < 0.005)
    }

    @Test @MainActor func mergesCollidingPerpendicularTablesIntoSingleLShapedDeskWithTwoWingEntity() {
        let sanitizer = RoomCaptureSanitizer()

        // Main wing: 1.50m x 0.60m running along X (yaw = 0) at Z = -1.65m (spans X: [-0.75, +0.75], Z: [-1.95, -1.35])
        let mainWing = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(0.0, 0.0, -1.65),
            dimensions: SIMD3<Float>(1.50, 0.75, 0.60),
            rotationYaw: 0
        )

        // Return wing: 1.20m x 0.60m running along Z (yaw = pi/2) at X = 0.45m, Z = -1.35m (spans X: [+0.15, +0.75], Z: [-1.95, -0.75])
        let returnWing = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(0.45, 0.0, -1.35),
            dimensions: SIMD3<Float>(1.20, 0.75, 0.60),
            rotationYaw: .pi / 2
        )

        let sanitized = sanitizer.sanitize(
            objects: [mainWing, returnWing],
            roomWidth: 5.0,
            roomLength: 5.0
        )

        #expect(sanitized.count == 1)
        #expect(sanitized[0].category == "desk")
        #expect(sanitized[0].name == "L-Shaped Desk")
        #expect(abs(sanitized[0].dimensions.x - 1.50) < 0.02)
        #expect(abs(sanitized[0].dimensions.z - 1.20) < 0.02)
        #expect(abs(sanitized[0].dimensions.y - 0.75) < 0.01)

        // Verify RealityKit entity constructs 2 non-overlapping L-wings rather than a single solid block
        let furniture = Furniture(
            name: sanitized[0].name,
            category: sanitized[0].category,
            positionX: sanitized[0].position.x,
            positionY: sanitized[0].position.y,
            positionZ: sanitized[0].position.z,
            rotationYaw: sanitized[0].rotationYaw,
            length: sanitized[0].dimensions.z,
            width: sanitized[0].dimensions.x,
            height: sanitized[0].dimensions.y
        )
        let entity = FurnitureEntityFactory.createEntity(for: furniture)
        let childNames = Set(entity.children.map { $0.name })
        #expect(childNames.contains("MainWingMesh"))
        #expect(childNames.contains("ReturnWingMesh"))
    }

    @Test func mergesCollinearSplitTablesIntoSingleUnifiedDesk() {
        let sanitizer = RoomCaptureSanitizer()

        // Two collinear 0.80m x 0.60m desk halves touching at X = 0.0m
        let leftHalf = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(-0.40, 0.0, 0.0),
            dimensions: SIMD3<Float>(0.80, 0.75, 0.60),
            rotationYaw: 0
        )
        let rightHalf = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(0.40, 0.0, 0.0),
            dimensions: SIMD3<Float>(0.80, 0.75, 0.60),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [leftHalf, rightHalf],
            roomWidth: 5.0,
            roomLength: 5.0
        )

        #expect(sanitized.count == 1)
        #expect(sanitized[0].category == "desk")
        #expect(sanitized[0].name == "Work Desk")
        #expect(abs(sanitized[0].dimensions.x - 1.60) < 0.02)
        #expect(abs(sanitized[0].dimensions.z - 0.60) < 0.02)
    }

    @Test func mergesCollidingStorageCredenzaAndTableWingFromRealScanIntoLShapedDesk() {
        let sanitizer = RoomCaptureSanitizer()
        let floorLevel: Float = -1.176

        // Exact telemetry from real iPhone RoomPlan scan (Storage0 + Table2 + Television0):
        // Apple RoomPlan classifies the drawer/credenza main wing of the L-shaped desk as "storage"
        // and the perpendicular return wing as "table".
        let storageMainWing = ScannedObjectPayload(
            rawCategory: "storage",
            position: SIMD3<Float>(-1.1733, -0.7697, 2.1957),
            dimensions: SIMD3<Float>(1.9858, 0.8128, 0.5795),
            rotationYaw: atan2(-0.5386, -0.8426)
        )
        let tableReturnWing = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(-2.1406, -0.7885, 2.2595),
            dimensions: SIMD3<Float>(1.1468, 0.7750, 0.6287),
            rotationYaw: atan2(0.8426, -0.5386)
        )
        let standingTV = ScannedObjectPayload(
            rawCategory: "television",
            position: SIMD3<Float>(-0.9683, -0.0585, 2.0228),
            dimensions: SIMD3<Float>(1.1023, 0.6650, 0.0884),
            rotationYaw: atan2(-0.5386, -0.8426)
        )

        let sanitized = sanitizer.sanitize(
            objects: [storageMainWing, tableReturnWing, standingTV],
            roomWidth: 4.5,
            roomLength: 5.0,
            floorLevel: floorLevel
        )

        // Storage0 and Table2 must merge into a single L-Shaped Desk, plus Television0 on top
        #expect(sanitized.count == 2)
        #expect(sanitized[0].category == "desk")
        #expect(sanitized[0].name == "L-Shaped Desk")
        #expect(abs(sanitized[0].dimensions.x - 2.164) < 0.05)
        #expect(abs(sanitized[0].dimensions.z - 1.326) < 0.05)
        #expect(abs(sanitized[0].dimensions.y - 0.8128) < 0.01)

        // Television0 must still resolve its base elevation flush onto the top of the 0.8128m wing
        #expect(sanitized[1].category == "television")
        #expect(abs(sanitized[1].position.y - (floorLevel + 0.8128)) < 0.01)
    }

    @Test @MainActor func mapperNormalizesScannedRoomFurnitureCoordinatesToFloorZeroAndCenteredLocalOrigin() throws {
        let walls = [
            ScannedWallPayload(position: [3.0, 0.3, 0.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: 0),
            ScannedWallPayload(position: [3.0, 0.3, -4.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: 0),
            ScannedWallPayload(position: [1.0, 0.3, -2.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: .pi / 2),
            ScannedWallPayload(position: [5.0, 0.3, -2.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: .pi / 2)
        ]
        // Centroid of room is at X = 3.0, Z = -2.0, floorLevel = -1.25m
        let bedObject = ScannedObjectPayload(
            rawCategory: "bed",
            position: SIMD3<Float>(3.0, -1.25, -2.0),
            dimensions: SIMD3<Float>(1.6, 1.0, 2.0),
            rotationYaw: .pi / 2
        )
        let deskObject = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(4.5, -1.25, -2.0),
            dimensions: SIMD3<Float>(1.2, 0.75, 0.6),
            rotationYaw: .pi / 2
        )

        let payload = CapturedRoomPayload(
            roomLength: 4.0,
            roomWidth: 4.0,
            roomHeight: 2.6,
            floorLevel: -1.25,
            walls: walls,
            openings: [],
            objects: [bedObject, deskObject]
        )

        let mapper = RoomCaptureMapper()
        let room = mapper.mapToRoom(payload: payload, roomName: "Normalized Scanned Room")

        #expect(room.layouts.count == 1)
        let layout = room.layouts[0]
        #expect(layout.furnitures.count == 2)

        for furniture in layout.furnitures {
            // Invariant: Floor-grounded furniture must have positionY == 0.0, NOT negative floorLevel (-1.25)
            #expect(furniture.positionY == 0.0)
            // Invariant: Horizontal coordinates must be centered around (0, 0)
            #expect(furniture.positionX >= -2.1 && furniture.positionX <= 2.1)
            #expect(furniture.positionZ >= -2.1 && furniture.positionZ <= 2.1)
        }

        let bed = try #require(layout.furnitures.first(where: { $0.category == "bed" }))
        // Bed was at the room center (3.0, -2.0) in camera coordinates -> must be at (0, 0) in normalized space
        #expect(abs(bed.positionX) < 0.05)
        #expect(abs(bed.positionZ) < 0.05)
    }

    @Test @MainActor func roomSceneControllerMigratesLegacyNegativeYFurnitureInPlace() async throws {
        let walls = [
            ScannedWallPayload(position: [3.0, 0.3, 0.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: 0),
            ScannedWallPayload(position: [3.0, 0.3, -4.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: 0),
            ScannedWallPayload(position: [1.0, 0.3, -2.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: .pi / 2),
            ScannedWallPayload(position: [5.0, 0.3, -2.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: .pi / 2)
        ]
        let room = Room(name: "Legacy Scanned Room", length: 4.0, width: 4.0, height: 2.6)
        room.planSnapshotData = try JSONEncoder().encode(RoomPlanSnapshot(walls: walls, floorLevel: -1.25))

        let legacyFurniture = Furniture(
            name: "Legacy Bed",
            category: "bed",
            positionX: 3.0,
            positionY: -1.25, // Legacy negative Y in camera tracking space
            positionZ: -2.0,
            rotationYaw: .pi / 2,
            length: 2.0,
            width: 1.6,
            height: 1.0
        )
        let legacyShelf = Furniture(
            name: "Legacy Shelf",
            category: "storage",
            positionX: 4.5, // in camera tracking coordinates near east wall
            positionY: -0.05, // elevated camera Y (above -0.3m, previously skipped)
            positionZ: -2.0,
            rotationYaw: .pi / 2,
            length: 0.4,
            width: 1.2,
            height: 0.3
        )
        let layout = Layout(name: "Legacy Layout")
        layout.furnitures.append(legacyFurniture)
        layout.furnitures.append(legacyShelf)
        room.layouts.append(layout)

        let controller = RoomSceneController(room: room, layout: layout)
        await controller.load()

        // Migration verification: furniture coordinates migrated in-place
        #expect(legacyFurniture.positionY == 0.0)
        #expect(abs(legacyFurniture.positionX) < 0.05)
        #expect(abs(legacyFurniture.positionZ) < 0.05)

        // Elevated shelf migration: shelf is placed inside the room and elevated
        #expect(legacyShelf.positionY >= 1.0)
        #expect(legacyShelf.positionX >= -2.0 && legacyShelf.positionX <= 2.0)
        #expect(legacyShelf.positionZ >= -2.0 && legacyShelf.positionZ <= 2.0)

        // Entity verification: 3D entity spawned at floor level
        let entity = try #require(controller.furnitureEntity(for: legacyFurniture.id))
        #expect(abs(entity.position.y) < 0.05)
        #expect(abs(entity.position.x) < 0.05)
        #expect(abs(entity.position.z) < 0.05)
    }

    @Test func discardsAirborneWallFloatingChairArtifacts() {
        let sanitizer = RoomCaptureSanitizer()
        let floorLevel: Float = -1.40

        // Legitimate floor chair: bottom rests at floorLevel
        let groundChair = ScannedObjectPayload(
            rawCategory: "chair",
            position: SIMD3<Float>(0.0, -0.95, 0.0), // bottom = -0.95 - 0.45 = -1.40 (floorLevel)
            dimensions: SIMD3<Float>(0.60, 0.90, 0.60),
            rotationYaw: 0
        )

        // Airborne wall artifact: whiteboard/acoustic panel misclassified as chair at eye level
        let wallArtifact = ScannedObjectPayload(
            rawCategory: "chair",
            position: SIMD3<Float>(0.0, 0.10, 2.0), // bottom = 0.10 - 0.40 = -0.30 (1.10m above floor)
            dimensions: SIMD3<Float>(0.60, 0.80, 0.25),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [groundChair, wallArtifact],
            roomWidth: 4.5,
            roomLength: 7.0,
            floorLevel: floorLevel
        )

        // Invariant: Wall artifact must be discarded; only legitimate ground chair survives
        #expect(sanitized.count == 1)
        #expect(sanitized.first?.category == "chair")
        #expect(abs(sanitized[0].position.z) < 0.5)
    }

    @Test func mergesSplitChairBackrestAndSeatIntoSingleUnifiedChair() {
        let sanitizer = RoomCaptureSanitizer()
        let floorLevel: Float = -1.40

        // Chair backrest (vertical, tall, resting near floor)
        let backrest = ScannedObjectPayload(
            rawCategory: "chair",
            position: SIMD3<Float>(1.20, -0.95, 0.50), // bottom = -1.40
            dimensions: SIMD3<Float>(0.55, 0.90, 0.25),
            rotationYaw: .pi / 2
        )

        // Chair seat cushion (horizontal, flat, elevated near table height)
        let seat = ScannedObjectPayload(
            rawCategory: "chair",
            position: SIMD3<Float>(1.20, -0.90, 0.35), // bottom = -0.90 - 0.10 = -1.00 (0.40m above floor)
            dimensions: SIMD3<Float>(0.55, 0.20, 0.50),
            rotationYaw: .pi / 2
        )

        let sanitized = sanitizer.sanitize(
            objects: [backrest, seat],
            roomWidth: 5.0,
            roomLength: 5.0,
            floorLevel: floorLevel
        )

        // Invariant: The two components must be merged into 1 unified chair entity
        #expect(sanitized.count == 1)
        let chair = sanitized[0]
        #expect(chair.category == "chair")
        // Invariant: Combined chair must ground flush to floorLevel
        #expect(chair.position.y == floorLevel)
        // Invariant: Combined height covers the full backrest height
        #expect(chair.dimensions.y >= 0.85)
        // Invariant: Combined depth covers the seat depth
        #expect(chair.dimensions.z >= 0.45)
    }

    @Test func tuckedChairUnderConferenceTableNeverElevatesToTableHeight() throws {
        let sanitizer = RoomCaptureSanitizer()
        let floorLevel: Float = -1.40

        // Conference Table: height 0.75m, floor at -1.40m, tabletop at -0.65m
        let table = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(0.0, -1.025, 0.0), // bottom = -1.40, top = -0.65
            dimensions: SIMD3<Float>(1.20, 0.75, 2.50),
            rotationYaw: 0
        )

        // Chair tucked into the side of the table
        let chair = ScannedObjectPayload(
            rawCategory: "chair",
            position: SIMD3<Float>(0.45, -0.95, 0.0),
            dimensions: SIMD3<Float>(0.60, 0.90, 0.60),
            rotationYaw: 0
        )

        let sanitized = sanitizer.sanitize(
            objects: [table, chair],
            roomWidth: 5.0,
            roomLength: 5.0,
            floorLevel: floorLevel
        )

        let chairResult = try #require(sanitized.first(where: { $0.category == "chair" }))
        // Invariant: Chair must NEVER snap to tabletop height (-0.65m); it must ground flush at floorLevel (-1.40m)
        #expect(chairResult.position.y == floorLevel)
    }

    @Test @MainActor func proceduralTableGeneratesOpenLegroomGeometry() {
        let table = Furniture(
            name: "Conference Table",
            category: "table",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            rotationYaw: 0,
            length: 2.40,
            width: 1.20,
            height: 0.75
        )

        let entity = FurnitureEntityFactory.createEntity(for: table)
        let childNames = Set(entity.children.map { $0.name })

        // Invariant: Procedural table must feature tabletop mesh and supporting corner legs
        #expect(childNames.contains("TabletopMesh"))
        #expect(childNames.contains("TableLegMesh_FL"))
        #expect(childNames.contains("TableLegMesh_FR"))
        #expect(childNames.contains("TableLegMesh_BL"))
        #expect(childNames.contains("TableLegMesh_BR"))
    }
}
