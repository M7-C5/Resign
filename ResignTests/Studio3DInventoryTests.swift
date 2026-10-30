//
//  Studio3DInventoryTests.swift
//  ResignTests
//

import Testing
import SwiftData
import simd
import CoreGraphics
@testable import Resign

@Suite("Studio 3D Inventory & Archival Tests")
struct Studio3DInventoryTests {

    @Test @MainActor func archiveFurnitureMarksItemArchivedAndDeselects() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Inventory Room", length: 5.0, width: 4.0, height: 2.6)
        context.insert(room)

        let layout = Layout(name: "Test Layout")
        room.layouts.append(layout)

        let bed = Furniture(name: "Queen Bed", category: "bed", positionX: -1.0, positionY: 0.0, positionZ: -0.5, rotationYaw: 0, length: 2.0, width: 1.6, height: 0.9)
        let desk = Furniture(name: "Work Desk", category: "desk", positionX: 1.0, positionY: 0.0, positionZ: 0.5, rotationYaw: 0, length: 1.4, width: 0.7, height: 0.75)
        layout.furnitures.append(contentsOf: [bed, desk])
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: bed.id, in: layout)
        #expect(viewModel.selectedFurnitureID == bed.id)

        // Archive bed
        viewModel.archiveFurniture(id: bed.id, in: layout, context: context)

        #expect(bed.isArchived == true)
        #expect(viewModel.selectedFurnitureID == nil)
        #expect(viewModel.archivedFurnitures(in: layout).count == 1)
        #expect(viewModel.archivedFurnitures(in: layout).first?.id == bed.id)
        #expect(viewModel.activeFurnitures(in: layout).count == 1)
        #expect(viewModel.activeFurnitures(in: layout).first?.id == desk.id)
    }

    @Test @MainActor func restoreFurnitureUnarchivesPlacesAndSelects() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Inventory Room", length: 5.0, width: 4.0, height: 2.6)
        context.insert(room)

        let layout = Layout(name: "Test Layout")
        room.layouts.append(layout)

        let sofa = Furniture(name: "Sofa", category: "sofa", positionX: 0.0, positionY: 0.0, positionZ: 0.0, rotationYaw: 0, length: 2.0, width: 0.9, height: 0.8, isArchived: true)
        layout.furnitures.append(sofa)
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.roomHorizontalBounds = (minX: -2.0, maxX: 2.0, minZ: -1.5, maxZ: 1.5)

        // Restore to target position
        let targetPos = SIMD2<Float>(0.5, -0.2)
        let restoredResult = viewModel.restoreFurniture(id: sofa.id, to: targetPos, in: layout, context: context)

        #expect(sofa.isArchived == false)
        #expect(viewModel.selectedFurnitureID == sofa.id)
        #expect(restoredResult != nil)
        #expect(abs(sofa.positionX - 0.5) < 0.001)
        #expect(abs(sofa.positionZ - (-0.2)) < 0.001)
        #expect(viewModel.archivedFurnitures(in: layout).isEmpty)
        #expect(viewModel.activeFurnitures(in: layout).count == 1)
    }

    @Test @MainActor func restoreFurnitureClampsToInteriorDrywallLimits() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Bounded Room", length: 4.0, width: 4.0, height: 2.6)
        context.insert(room)

        let layout = Layout(name: "Layout")
        room.layouts.append(layout)

        let chair = Furniture(name: "Desk Chair", category: "chair", positionX: 0, positionY: 0, positionZ: 0, rotationYaw: 0, length: 0.6, width: 0.6, height: 0.9, isArchived: true)
        layout.furnitures.append(chair)
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.roomHorizontalBounds = (minX: -1.8, maxX: 1.8, minZ: -1.8, maxZ: 1.8)

        // Try to place far outside wall limits (e.g. at 5.0, 5.0)
        let farTarget = SIMD2<Float>(5.0, 5.0)
        _ = viewModel.restoreFurniture(id: chair.id, to: farTarget, in: layout, context: context)

        let halfW = chair.width / 2.0
        let halfL = chair.length / 2.0
        #expect(chair.positionX <= 1.8 - halfW + 0.001)
        #expect(chair.positionZ <= 1.8 - halfL + 0.001)
        #expect(chair.isArchived == false)
    }

    @Test @MainActor func archivedFurnitureDoesNotActAsCollisionObstacle() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Collision Room", length: 6.0, width: 6.0, height: 2.6)
        context.insert(room)

        let layout = Layout(name: "Layout")
        room.layouts.append(layout)

        let bed = Furniture(name: "Queen Bed", category: "bed", positionX: 0.0, positionY: 0.0, positionZ: 0.0, rotationYaw: 0, length: 2.0, width: 1.6, height: 0.9)
        let table = Furniture(name: "Coffee Table", category: "table", positionX: 0.0, positionY: 0.0, positionZ: 0.0, rotationYaw: 0, length: 1.0, width: 1.0, height: 0.5, isArchived: true)
        layout.furnitures.append(contentsOf: [bed, table])
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.roomHorizontalBounds = (minX: -2.5, maxX: 2.5, minZ: -2.5, maxZ: 2.5)
        viewModel.selectFurniture(id: bed.id, in: layout)

        // Bed is positioned at (0, 0), right where table was located when unarchived.
        // Because table is archived, moving bed to (0, 0) must NOT collide with table.
        let result = viewModel.moveSelectedFurniture(to: SIMD2<Float>(0.0, 0.0), in: layout, context: context)
        #expect(result != nil)
        #expect(result?.isColliding == false)
    }

    @Test func archiveTargetProximityCalculation() {
        let targetCenter = CGPoint(x: 46, y: 750)
        let radius: CGFloat = 64.0

        // Point inside radius
        let closePoint = CGPoint(x: 60, y: 730)
        #expect(Studio3DViewModel.isWithinArchiveTarget(point: closePoint, targetCenter: targetCenter, radius: radius) == true)

        // Point exactly at center
        #expect(Studio3DViewModel.isWithinArchiveTarget(point: targetCenter, targetCenter: targetCenter, radius: radius) == true)

        // Point outside radius
        let farPoint = CGPoint(x: 200, y: 750)
        #expect(Studio3DViewModel.isWithinArchiveTarget(point: farPoint, targetCenter: targetCenter, radius: radius) == false)
    }
}
