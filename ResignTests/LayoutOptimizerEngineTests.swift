//
//  LayoutOptimizerEngineTests.swift
//  ResignTests
//
//  Created by Antigravity on 26/10/26.
//

import Testing
import Foundation
@testable import Resign

@Suite("Layout Optimizer Engine Parametric Solver Tests")
struct LayoutOptimizerEngineTests {

    let optimizer = LayoutOptimizerEngine()
    let clearanceEngine = SpatialClearanceEngine()

    @Test @MainActor func parametricSolverAdaptsToDifferentRoomDimensions() {
        // Test Room 1: Standard 5.0m x 4.2m
        let roomStandard = Room(length: 4.2, width: 5.0, height: 2.6)
        let door1 = RoomOpening(type: "door", posX: -1.5, posY: 0.0, posZ: 2.1, width: 0.9, height: 2.1)
        let window1 = RoomOpening(type: "window", posX: 2.5, posY: 1.45, posZ: 0.0, width: 1.6, height: 1.2)
        roomStandard.openings = [door1, window1]

        let baseLayout = RoomRepository.createViolatingMockRoom().layouts.first!
        let settings = SolverSettings(
            pinnedItemIds: [],
            mustHaveItemIds: [],
            goalWeights: GoalWeights(spacious: 0.8, balanced: 0.6, reachable: 0.7)
        )

        let variants = optimizer.generateLayouts(for: roomStandard, from: baseLayout, settings: settings)
        #expect(variants.count == 3)

        for variant in variants {
            // 1. All furniture must remain inside room perimeter
            let halfW = roomStandard.width / 2.0
            let halfL = roomStandard.length / 2.0
            for item in variant.furnitures {
                #expect(item.positionX >= -halfW && item.positionX <= halfW, "Item \(item.name) out of X bounds")
                #expect(item.positionZ >= -halfL && item.positionZ <= halfL, "Item \(item.name) out of Z bounds")
            }

            // 2. Door swing must be 100% unobstructed
            let doorViolations = clearanceEngine.checkDoorSwing(furnitures: variant.furnitures, doors: [door1])
            #expect(doorViolations.isEmpty, "Layout \(variant.name) must not obstruct door swing")
        }
    }

    @Test @MainActor func parametricSolverAdaptsToLargeRoom() {
        // Test Room 2: Large 7.0m x 5.0m
        let largeRoom = Room(length: 5.0, width: 7.0, height: 2.8)
        let door = RoomOpening(type: "door", posX: -2.5, posY: 0.0, posZ: 2.5, width: 1.0, height: 2.2)
        let window = RoomOpening(type: "window", posX: 3.5, posY: 1.5, posZ: 0.0, width: 2.0, height: 1.4)
        largeRoom.openings = [door, window]

        let baseLayout = RoomRepository.createViolatingMockRoom().layouts.first!
        let settings = SolverSettings()

        let variants = optimizer.generateLayouts(for: largeRoom, from: baseLayout, settings: settings)
        #expect(variants.count == 3)

        for variant in variants {
            let halfW = largeRoom.width / 2.0
            let halfL = largeRoom.length / 2.0
            for item in variant.furnitures {
                #expect(item.positionX >= -halfW && item.positionX <= halfW)
                #expect(item.positionZ >= -halfL && item.positionZ <= halfL)
            }
            let doorViolations = clearanceEngine.checkDoorSwing(furnitures: variant.furnitures, doors: [door])
            #expect(doorViolations.isEmpty)
        }
    }

    @Test @MainActor func generatedRecommendationsHaveZeroCriticalViolations() {
        let room = RoomRepository.createViolatingMockRoom()
        let baseLayout = room.layouts.first!
        let settings = SolverSettings()

        let variants = optimizer.generateLayouts(for: room, from: baseLayout, settings: settings)
        #expect(variants.count == 3)

        for variant in variants {
            let doorViolations = clearanceEngine.checkDoorSwing(furnitures: variant.furnitures, doors: room.openings.filter { $0.type.localizedCaseInsensitiveContains("door") })
            #expect(doorViolations.isEmpty, "Layout \(variant.name) must clear door swings")

            let deskViolations = clearanceEngine.checkDeskClearance(furnitures: variant.furnitures, roomLength: room.length, roomWidth: room.width)
            #expect(deskViolations.isEmpty, "Layout \(variant.name) must provide compliant desk pullback")

            let criticalWalkways = clearanceEngine.checkWalkwayClearances(furnitures: variant.furnitures, roomLength: room.length, roomWidth: room.width).filter { $0.severity == .critical }
            #expect(criticalWalkways.isEmpty, "Layout \(variant.name) must have zero critical walkway bottlenecks: \(criticalWalkways.map(\.message).joined(separator: "; "))")
        }

        // Verify that variants offer distinct, perceptible spatial differences
        let layout1 = variants[0]
        let layout2 = variants[1]
        let layout3 = variants[2]

        var diff12 = 0
        for a in layout1.furnitures {
            guard let b = layout2.furnitures.first(where: { $0.name == a.name }) else { continue }
            if hypot(a.positionX - b.positionX, a.positionZ - b.positionZ) > 0.4 || abs(a.rotationYaw - b.rotationYaw) > 0.1 {
                diff12 += 1
            }
        }
        #expect(diff12 >= 2, "Layout 1 and Layout 2 must differ in at least 2 items")

        var diff13 = 0
        for a in layout1.furnitures {
            guard let b = layout3.furnitures.first(where: { $0.name == a.name }) else { continue }
            if hypot(a.positionX - b.positionX, a.positionZ - b.positionZ) > 0.4 || abs(a.rotationYaw - b.rotationYaw) > 0.1 {
                diff13 += 1
            }
        }
        #expect(diff13 >= 2, "Layout 1 and Layout 3 must differ in at least 2 items")
    }

    @Test @MainActor func pinnedTVRemainsAtInitialPositionWithZeroCriticalViolationsAcrossVariants() {
        let room = RoomRepository.createViolatingMockRoom()
        let baseLayout = room.layouts.first!
        let tv = baseLayout.furnitures.first { $0.category == "television" || $0.name.localizedCaseInsensitiveContains("tv") }!

        let settings = SolverSettings(
            pinnedItemIds: [tv.id],
            mustHaveItemIds: baseLayout.furnitures.map(\.id),
            goalWeights: GoalWeights(spacious: 0.8, balanced: 0.6, reachable: 0.7)
        )

        let variants = optimizer.generateLayouts(for: room, from: baseLayout, settings: settings)
        #expect(variants.count == 3)

        for variant in variants {
            let variantTV = variant.furnitures.first { $0.name == tv.name }!
            #expect(variantTV.positionX == tv.positionX, "Pinned TV X must remain unchanged in \(variant.name)")
            #expect(variantTV.positionZ == tv.positionZ, "Pinned TV Z must remain unchanged in \(variant.name)")

            let doorViolations = clearanceEngine.checkDoorSwing(furnitures: variant.furnitures, doors: room.openings.filter { $0.type.localizedCaseInsensitiveContains("door") })
            #expect(doorViolations.isEmpty, "Layout \(variant.name) with pinned TV must clear door swings")

            let deskViolations = clearanceEngine.checkDeskClearance(furnitures: variant.furnitures, roomLength: room.length, roomWidth: room.width)
            #expect(deskViolations.isEmpty, "Layout \(variant.name) with pinned TV must provide compliant desk pullback")

            let criticalWalkways = clearanceEngine.checkWalkwayClearances(furnitures: variant.furnitures, roomLength: room.length, roomWidth: room.width).filter { $0.severity == .critical }
            #expect(criticalWalkways.isEmpty, "Layout \(variant.name) with pinned TV must have zero critical walkway bottlenecks: \(criticalWalkways.map(\.message).joined(separator: "; "))")
        }
    }
}

