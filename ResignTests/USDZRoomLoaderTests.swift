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
}
