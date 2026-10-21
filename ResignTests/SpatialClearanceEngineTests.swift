//
//  SpatialClearanceEngineTests.swift
//  ResignTests
//
//  Created by Antigravity on 21/10/26.
//

import Testing
import Foundation
@testable import Resign

@Suite("Spatial Clearance Engine Tests (Panero & Zelnik Rules)")
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
        // Placed along Z axis: sofa edge is at Z = +0.5. Coffee table placed at Z = 1.0 (gap = 0.5m = 50cm)
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
        // Bed and desk with gap of 80 cm (between 76.2 cm and 91.4 cm -> R2 warning)
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
        // Bed right edge: -1.5 + 0.8 = -0.7. Desk left edge: 0.1 - 0.3 = -0.2. Gap = 0.5m -> critical
        // Let's place desk at X = -0.7 + 0.85 + 0.3 = 0.45. Gap = 0.85m = 85 cm (R2 warning)
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

        // Desk near wall where chair pull-back is only 50 cm (< 76.2 cm minimum R3)
        // North wall is at Z = -2.1. Desk at Z = -1.8, length = 0.6. Back edge at -2.1, front edge at -1.5.
        // Seating is in front towards +Z. If a wall or obstacle is 50 cm away from desk seating edge:
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
        // Chair placed behind desk
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
        // Obstacle directly behind chair at Z = -0.55 (clearance behind chair is only 30 cm)
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

        // Bed placed with only 40 cm between bed side and wall (< 66 cm minimum R4)
        // Room width 5.0m (-2.5 to 2.5). Bed width 1.6m. Placed at X = -1.5:
        // Left edge: -1.5 - 0.8 = -2.3m. West wall is at -2.5m. Distance to wall = 0.2m = 20 cm (< 66 cm)!
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

        // Door located at South wall: posX: -1.5, posZ: 2.1, width: 0.9m
        let door = RoomOpening(type: "door", posX: -1.5, posY: 0.0, posZ: 2.1, width: 0.9, height: 2.1)

        // Chair placed inside door swing radius: at X = -1.5, Z = 1.6 (within 0.9m swing arc)
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
}
