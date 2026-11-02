//
//  LayoutValidationEngineTests.swift
//  ResignTests
//

import Testing
import Foundation
@testable import Resign

@Suite("Layout Validation Engine & Geometry Consistency Tests")
struct LayoutValidationEngineTests {

    let validator = LayoutValidationEngine()
    let clearance = SpatialClearanceEngine()

    private func piece(
        _ name: String, _ category: String,
        x: Float, z: Float, w: Float, l: Float, yaw: Float = 0, h: Float = 0.8
    ) -> Furniture {
        Furniture(name: name, category: category, positionX: x, positionZ: z, rotationYaw: yaw, length: l, width: w, height: h)
    }

    @Test @MainActor func overlappingItemsAreReportedWithDepth() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let a = piece("Sofa", "sofa", x: 0, z: 0, w: 2.0, l: 0.85)
        let b = piece("Stool", "chair", x: 0.5, z: 0.2, w: 0.45, l: 0.45)
        let report = validator.validate(room: room, furnitures: [a, b])
        #expect(report.overlaps.count == 1)
        #expect((report.overlaps.first?.depthCm ?? 0) > 1.0)
        #expect(!report.isClean)
    }

    @Test @MainActor func touchingItemsDoNotOverlap() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let a = piece("A", "other", x: 0, z: 0, w: 1.0, l: 1.0)
        let b = piece("B", "other", x: 1.0, z: 0, w: 1.0, l: 1.0)
        #expect(validator.validate(room: room, furnitures: [a, b]).overlaps.isEmpty)
    }

    @Test @MainActor func itemsOutsideTheRoomAreReported() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let inside = piece("Inside", "other", x: 0, z: 0, w: 1, l: 1)
        let outside = piece("Outside", "other", x: 2.3, z: 0, w: 1, l: 1)
        let report = validator.validate(room: room, furnitures: [inside, outside])
        #expect(report.outOfBounds.map(\.name) == ["Outside"])
    }

    @Test @MainActor func itemBlockingTheTVSofaSightlineIsReported() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let tv = piece("TV", "television", x: 0, z: -1.9, w: 1.4, l: 0.38)
        let sofa = piece("Sofa", "sofa", x: 0, z: 1.65, w: 2.0, l: 0.85)
        let blocker = piece("Stool", "chair", x: 0.1, z: 0, w: 0.45, l: 0.45)

        let blocked = validator.validate(room: room, furnitures: [tv, sofa, blocker])
        #expect(blocked.sightlineBlockers == [blocker.id])

        blocker.positionX = 2.0
        let clear = validator.validate(room: room, furnitures: [tv, sofa, blocker])
        #expect(clear.sightlineBlockers.isEmpty)
    }

    @Test @MainActor func referenceRoomFixtureMatchesRenderedMeshGeometry() {
        // The fixture, the USDZ meshes and the clearance engine must agree: the starting
        // arrangement must have no overlaps and nothing outside the walls.
        for room in [RoomRepository.createStandardMockRoom(), RoomRepository.createViolatingMockRoom()] {
            let report = validator.validate(room: room, furnitures: room.layouts.first!.furnitures)
            #expect(report.overlaps.isEmpty, "Fixture overlaps: \(report.overlaps.map { "\($0.nameA)/\($0.nameB)" })")
            #expect(report.outOfBounds.isEmpty, "Fixture out of bounds: \(report.outOfBounds.map(\.name))")
        }
    }

    @Test @MainActor func deskRearClearanceFollowsTheActualPullAxis() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let desk = piece("Work Desk", "desk", x: 2.15, z: 0, w: 0.65, l: 1.2, h: 0.75)
        let chair = piece("Chair", "chair", x: 1.55, z: 0, w: 0.44, l: 0.44, h: 0.9)
        // Wardrobe whose east face sits 40 cm behind the chair's pull-back side (chair west edge = 1.33).
        let wardrobe = piece("Wardrobe", "closet", x: 0.63, z: 0, w: 0.6, l: 1.2, h: 2.1)

        let tight = clearance.checkDeskClearance(furnitures: [desk, chair, wardrobe], roomLength: room.length, roomWidth: room.width)
        #expect(tight.contains { $0.ruleId == PaneroZelnikRule.deskRearClearance })
        if let violation = tight.first(where: { $0.ruleId == PaneroZelnikRule.deskRearClearance }) {
            #expect(abs(violation.measuredClearanceCm - 40.0) < 1.0)
        }

        wardrobe.positionX = 0.0
        let roomy = clearance.checkDeskClearance(furnitures: [desk, chair, wardrobe], roomLength: room.length, roomWidth: room.width)
        #expect(roomy.isEmpty)
    }

    @Test @MainActor func nearestWallClassificationHandlesNonSquareRooms() {
        // A door at x = 3.0, z = 2.1 in a 7.0 x 4.2 room sits on the SOUTH wall even though |x| > |z|.
        let wall = RoomWall.nearest(toX: 3.0, z: 2.1, halfWidth: 3.5, halfLength: 2.1)
        #expect(wall == .south)
        #expect(RoomWall.nearest(toX: 2.5, z: 0, halfWidth: 2.5, halfLength: 2.1) == .east)
    }

    @Test func orientationConventionPointsBackAtTheRequestedWall() {
        for category in ["bed", "desk", "chair", "sofa", "closet", "television"] {
            for wall in RoomWall.allCases {
                let yaw = FurnitureOrientation.yaw(forCategory: category, backTowards: wall.towardWall)
                let back = FurnitureOrientation.rotate(FurnitureOrientation.nativeBack(forCategory: category), yaw: yaw)
                #expect(abs(back.x - wall.towardWall.x) < 0.001 && abs(back.z - wall.towardWall.z) < 0.001,
                        "\(category) back must face \(wall)")
            }
        }
    }
}
