import Foundation
import Testing
import simd
@testable import Resign

@Suite("ScannedRoomPlanView footprint coordinate mapping")
struct ScannedRoomPlanViewTests {

    private func makeSnapshot() -> RoomPlanSnapshot {
        let walls = [
            ScannedWallPayload(position: [2.0, 1.3, 0.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: .pi / 4),
            ScannedWallPayload(position: [2.0, 1.3, -4.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: .pi / 4),
            ScannedWallPayload(position: [0.0, 1.3, -2.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: 3 * .pi / 4),
            ScannedWallPayload(position: [4.0, 1.3, -2.0], dimensions: [4.0, 2.6, 0.1], rotationYaw: 3 * .pi / 4)
        ]
        return RoomPlanSnapshot(walls: walls, floorLevel: -1.25)
    }

    @Test func normalizedFurniturePreservesLocalCoordinatesAndYaw() {
        let snapshot = makeSnapshot()
        // Normalized furniture already centered at local (0.5, -0.5) with local yaw = 0 (straight against wall)
        let normalizedItem = Furniture(
            name: "Work Desk",
            category: "desk",
            positionX: 0.5,
            positionY: 0.0, // Grounded floor level >= -0.3
            positionZ: -0.5,
            rotationYaw: 0.0,
            length: 1.4,
            width: 0.7,
            height: 0.75
        )

        let coords = ScannedRoomPlanView.footprintCoordinates(for: normalizedItem, scanPlan: snapshot)

        // Invariant: Normalized furniture must NOT be transformed again (no double-shift, no double-yaw)
        #expect(coords.position.x == 0.5)
        #expect(coords.position.y == -0.5)
        #expect(coords.yaw == 0.0)
    }

    @Test func legacyFurnitureTransformsViaScanPlan() {
        let snapshot = makeSnapshot()
        // Legacy unmigrated scan with negative Y floor level (-1.25m) and raw world camera coordinates
        let legacyItem = Furniture(
            name: "Legacy Bed",
            category: "bed",
            positionX: snapshot.centerX,
            positionY: -1.25, // Unmigrated legacy floor level < -0.3
            positionZ: snapshot.centerZ,
            rotationYaw: snapshot.yawRadians,
            length: 2.0,
            width: 1.6,
            height: 0.9
        )

        let coords = ScannedRoomPlanView.footprintCoordinates(for: legacyItem, scanPlan: snapshot)

        // Legacy furniture should be mapped through scanPlan to local coordinates (around center 0, 0)
        #expect(abs(coords.position.x) < 0.05)
        #expect(abs(coords.position.y) < 0.05)
        #expect(abs(coords.yaw) < 0.05)
    }

    @Test func nilScanPlanPassesThroughCoordinatesDirectly() {
        let item = Furniture(
            name: "Sofa",
            category: "sofa",
            positionX: 1.2,
            positionY: 0.0,
            positionZ: -1.0,
            rotationYaw: .pi / 2,
            length: 2.0,
            width: 0.85,
            height: 0.8
        )

        let coords = ScannedRoomPlanView.footprintCoordinates(for: item, scanPlan: nil)

        #expect(coords.position.x == 1.2)
        #expect(coords.position.y == -1.0)
        #expect(coords.yaw == .pi / 2)
    }
}
