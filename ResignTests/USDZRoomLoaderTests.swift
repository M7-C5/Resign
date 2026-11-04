//
//  USDZRoomLoaderTests.swift
//  ResignTests
//
//  Created by Antigravity on 21/10/26.
//

import Testing
import Foundation
import ModelIO
@testable import Resign

@Suite("Dynamic USDZ Room Loader Tests")
struct USDZRoomLoaderTests {

    @Test @MainActor func loadMockRoomFromUSDZDirectly() throws {
        guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
            #expect(Bool(false), "MockRoom.usdz must exist in Bundle.main")
            return
        }

        let loader = USDZRoomLoader()
        let room = try loader.loadRoom(from: url)

        // 1. Verify Room Dimensions (5.0m W x 4.2m L x 2.6m H)
        #expect(abs(room.width - 5.0) < 0.1, "Extracted room width should be approx 5.0m")
        #expect(abs(room.length - 4.2) < 0.1, "Extracted room length should be approx 4.2m")

        // 2. Verify Openings Extracted
        #expect(room.openings.count >= 2, "Should extract Window and Door openings from USDZ")
        let openingTypes = Set(room.openings.map(\.type))
        #expect(openingTypes.contains("window"))
        #expect(openingTypes.contains("door"))

        // 3. Verify Layout and Furniture Extracted
        #expect(room.layouts.count == 1)
        guard let layout = room.layouts.first else {
            #expect(Bool(false), "Parsed room must contain an initial layout")
            return
        }

        let furnitureNames = Set(layout.furnitures.map(\.name))
        #expect(furnitureNames.contains("Bed"))
        #expect(furnitureNames.contains("Desk"))
        #expect(furnitureNames.contains("Chair"))
        #expect(furnitureNames.contains("Sofa"))
        #expect(furnitureNames.contains("Closet"))
        #expect(furnitureNames.contains("TV"))

        // 4. Verify Bed dimensions and coordinates
        guard let bed = layout.furnitures.first(where: { $0.name == "Bed" }) else {
            #expect(Bool(false), "Bed must be present in parsed furniture")
            return
        }
        #expect(bed.category == "bed")
        #expect(abs(bed.width - 1.6) < 0.2, "Bed width should be ~1.6m")
        #expect(abs(bed.length - 2.0) < 0.2, "Bed length should be ~2.0m")

        // 5. Verify that extracted room directly feeds into clearance diagnostics and prompt builder
        let clearanceEngine = SpatialClearanceEngine()
        let violations = clearanceEngine.evaluate(room: room, layout: layout)
        #expect(violations is [SpatialViolation])

        let prompt = RoomDiagnosticPromptBuilder.buildPrompt(
            room: room,
            layout: layout,
            violations: violations,
            userPreference: "Focus on Productivity"
        )
        #expect(prompt.contains("500 cm") || prompt.contains("420 cm"))
        #expect(prompt.contains("Do NOT calculate 3D coordinates"))
    }

    @Test @MainActor func loadRoom2FromUSDZExtractsCenteredFurnitureAndBounds() throws {
        guard let url = Bundle.main.url(forResource: "Room-2", withExtension: "usdz") else {
            #expect(Bool(false), "Room-2.usdz must exist in Bundle.main")
            return
        }

        let loader = USDZRoomLoader()
        let room = try loader.loadRoom(from: url)

        // Room span should be roughly 4.0m x 4.2m
        #expect(room.width > 3.5 && room.width < 5.5)
        #expect(room.length > 3.5 && room.length < 5.5)

        // Openings
        #expect(!room.openings.isEmpty, "Room-2 must contain door and window openings")

        // Furnitures
        guard let layout = room.layouts.first else {
            #expect(Bool(false), "Room-2 must contain an initial layout")
            return
        }
        #expect(layout.furnitures.count >= 4)

        // Bed must have realistic human dimensions, not 6x6 meters
        guard let bed = layout.furnitures.first(where: { $0.category == "bed" }) else {
            #expect(Bool(false), "Bed must be present in parsed furniture")
            return
        }
        #expect(bed.width > 1.2 && bed.width < 2.5)
        #expect(bed.length > 1.8 && bed.length < 2.5)
        #expect(bed.positionY == 0.0)

        // Table / Desk must have realistic dimensions, not 4.3x6.6 meters
        guard let desk = layout.furnitures.first(where: { $0.category == "desk" }) else {
            #expect(Bool(false), "Desk/Table must be present in parsed furniture")
            return
        }
        #expect(desk.width > 0.4 && desk.width < 2.0)
        #expect(desk.length > 0.4 && desk.length < 2.0)
        #expect(desk.positionY == 0.0)

        // Table and Bed must not be at the exact same position
        let dist = hypot(bed.positionX - desk.positionX, bed.positionZ - desk.positionZ)
        #expect(dist > 0.5, "Bed and Desk must not overlap at the same coordinates (dist was \(dist))")
    }
}
