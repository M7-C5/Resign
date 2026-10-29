//
//  Studio3DRearrangementTests.swift
//  ResignTests
//

import Testing
import Foundation
import SwiftData
import simd
@testable import Resign

@Suite("Studio 3D Rearrangement Tests")
struct Studio3DRearrangementTests {

    @Test @MainActor func loadsColoredMockRoomTwoWhenLayoutUSDZIsMissing() async throws {
        let room = Room(name: "Test Room", length: 4.5, width: 4.0, height: 2.7)
        let layout = Layout(name: "Test Layout")
        layout.usdzURL = URL(fileURLWithPath: "/non/existent/path/Room.usdz")
        room.layouts.append(layout)

        let controller = RoomSceneController(room: room, layout: layout)
        await controller.load()

        // Loads Room-2.usdz colored mock room reference environment
        #expect(controller.loadState == .loaded)
        #expect(controller.roomHorizontalBounds != nil)
    }

    @Test @MainActor func viewModelClampsUsingResolvedRoomHorizontalBounds() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let room = Room(name: "Bedroom", length: 6.0, width: 5.0, height: 2.7)
        let layout = Layout(name: "Original")
        let bed = Furniture(
            name: "Bed",
            category: "bed",
            positionX: -1.30,
            positionY: -1.22,
            positionZ: -0.30,
            rotationYaw: 0,
            length: 2.0,
            width: 1.6,
            height: 0.9
        )
        layout.furnitures.append(bed)
        room.layouts.append(layout)
        container.mainContext.insert(room)

        let viewModel = Studio3DViewModel()
        // Set Room-2 horizontal bounds: X [-3.30, 0.70], Z [-2.40, 1.80]
        viewModel.roomHorizontalBounds = (minX: -3.30, maxX: 0.70, minZ: -2.40, maxZ: 1.80)
        viewModel.selectFurniture(id: bed.id, in: layout)

        // Drag toward south wall (Z = -3.0): clamped to Z = -1.40 (never escapes out of south wall!)
        let southDrag = viewModel.moveSelectedFurniture(to: SIMD2<Float>(-1.30, -3.0), in: layout, context: container.mainContext)
        #expect(southDrag != nil)
        #expect(abs(bed.positionZ - (-1.40)) < 0.001)

        // Drag toward north wall (Z = +2.5): reaches edge of north wall at Z = 0.80
        let northDrag = viewModel.moveSelectedFurniture(to: SIMD2<Float>(-1.30, 2.5), in: layout, context: container.mainContext)
        #expect(northDrag != nil)
        #expect(abs(bed.positionZ - 0.80) < 0.001)
    }

    @Test @MainActor func viewModelMovesFurnitureWithinDrywallBoundaries() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let room = Room(name: "Bedroom", length: 6.0, width: 5.0, height: 2.7)
        let layout = Layout(name: "Original")
        let bed = Furniture(
            name: "Bed",
            category: "bed",
            positionX: 0,
            positionY: 0.45,
            positionZ: 0,
            rotationYaw: 0,
            length: 2.0,
            width: 1.6,
            height: 0.9
        )
        layout.furnitures.append(bed)
        room.layouts.append(layout)
        container.mainContext.insert(room)

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: bed.id, in: layout)

        // Move bed to valid floor coordinate (1.0, 1.0)
        let result = viewModel.moveSelectedFurniture(
            to: SIMD2<Float>(1.0, 1.0),
            in: layout,
            context: container.mainContext
        )

        #expect(result != nil)
        #expect(result?.isColliding == false)
        #expect(abs(bed.positionX - 1.0) < 0.001)
        #expect(abs(bed.positionZ - 1.0) < 0.001)
    }

    @Test @MainActor func viewModelClampsFurnitureWhenDraggedBeyondRoomWall() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        // Room: width = 5.0 (X: -2.5 to +2.5), length = 6.0 (Z: -3.0 to +3.0)
        let room = Room(name: "Bedroom", length: 6.0, width: 5.0, height: 2.7)
        let layout = Layout(name: "Original")
        // Bed: width = 1.6 (half = 0.8), length = 2.0 (half = 1.0)
        // Max valid X is 2.5 - 0.8 = 1.7
        let bed = Furniture(
            name: "Bed",
            category: "bed",
            positionX: 0,
            positionY: 0.45,
            positionZ: 0,
            rotationYaw: 0,
            length: 2.0,
            width: 1.6,
            height: 0.9
        )
        layout.furnitures.append(bed)
        room.layouts.append(layout)
        container.mainContext.insert(room)

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: bed.id, in: layout)

        // Try to drag bed out the wall to X = 4.0
        let result = viewModel.moveSelectedFurniture(
            to: SIMD2<Float>(4.0, 0),
            in: layout,
            context: container.mainContext
        )

        #expect(result != nil)
        #expect(result?.isColliding == false)
        #expect(abs(bed.positionX - 1.7) < 0.001)
        #expect(abs(bed.positionZ - 0.0) < 0.001)
    }

    @Test @MainActor func viewModelDetectsCollisionWithoutLockingMovementAndRevertsOnDeselect() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let room = Room(name: "Bedroom", length: 6.0, width: 5.0, height: 2.7)
        let layout = Layout(name: "Original")
        let bed = Furniture(
            name: "Bed",
            category: "bed",
            positionX: 0,
            positionY: 0.45,
            positionZ: 0,
            rotationYaw: 0,
            length: 2.0,
            width: 1.6,
            height: 0.9
        )
        let wardrobe = Furniture(
            name: "Wardrobe",
            category: "storage",
            positionX: 1.5,
            positionY: 1.0,
            positionZ: 0,
            rotationYaw: 0,
            length: 0.6,
            width: 1.0,
            height: 2.0
        )
        layout.furnitures.append(bed)
        layout.furnitures.append(wardrobe)
        room.layouts.append(layout)
        container.mainContext.insert(room)

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: bed.id, in: layout)

        // Move bed directly over wardrobe at (1.5, 0)
        let result = viewModel.moveSelectedFurniture(
            to: SIMD2<Float>(1.5, 0),
            in: layout,
            context: container.mainContext
        )

        // Permissive drag moves the piece visually but marks collision and red status
        #expect(result != nil)
        #expect(result?.isColliding == true)
        #expect(viewModel.isColliding == true)
        #expect(abs(bed.positionX - 1.5) < 0.001)

        // Deselecting while colliding reverts to the last non-colliding coordinates (0, 0)
        viewModel.deselectFurniture(in: layout, context: container.mainContext)
        #expect(viewModel.isColliding == false)
        #expect(bed.positionX == 0)
    }

    @Test @MainActor func viewModelRotatesFurnitureNinetyDegrees() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let room = Room(name: "Bedroom", length: 6.0, width: 5.0, height: 2.7)
        let layout = Layout(name: "Original")
        let desk = Furniture(
            name: "Desk",
            category: "desk",
            positionX: 0,
            positionY: 0.375,
            positionZ: 0,
            rotationYaw: 0,
            length: 0.7,
            width: 1.4,
            height: 0.75
        )
        layout.furnitures.append(desk)
        room.layouts.append(layout)
        container.mainContext.insert(room)

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: desk.id, in: layout)

        let rotated = viewModel.rotateSelectedFurniture90(in: layout, context: container.mainContext)
        #expect(rotated != nil)
        #expect(rotated?.isColliding == false)
        #expect(abs(desk.rotationYaw - (.pi / 2.0)) < 0.001)

        let rotatedAgain = viewModel.rotateSelectedFurniture90(in: layout, context: container.mainContext)
        #expect(rotatedAgain != nil)
        #expect(rotatedAgain?.isColliding == false)
        #expect(abs(desk.rotationYaw - .pi) < 0.001)
    }

    @Test @MainActor func viewModelRotatesFurnitureContinuouslyWithSnapping() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let room = Room(name: "Bedroom", length: 6.0, width: 5.0, height: 2.7)
        let layout = Layout(name: "Original")
        let desk = Furniture(
            name: "Desk",
            category: "desk",
            positionX: 0,
            positionY: 0.375,
            positionZ: 0,
            rotationYaw: 0,
            length: 0.7,
            width: 1.4,
            height: 0.75
        )
        layout.furnitures.append(desk)
        room.layouts.append(layout)
        container.mainContext.insert(room)

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: desk.id, in: layout)

        // Continuous drag to 0.75 rad (no snap)
        let freeRotate = viewModel.rotateSelectedFurniture(to: 0.75, in: layout, context: container.mainContext)
        #expect(freeRotate != nil)
        #expect(freeRotate?.didSnap == false)
        #expect(abs(desk.rotationYaw - 0.75) < 0.001)

        // Drag near 90° (1.52 rad within threshold) -> snaps to pi/2
        let snapRotate = viewModel.rotateSelectedFurniture(to: 1.52, in: layout, context: container.mainContext)
        #expect(snapRotate != nil)
        #expect(snapRotate?.didSnap == true)
        #expect(abs(desk.rotationYaw - (.pi / 2.0)) < 0.001)
    }

    @Test @MainActor func derivesInteriorDrywallLimitsWithoutWallThickness() async throws {
        let room = Room(name: "Test Room", length: 4.5, width: 4.0, height: 2.7)
        let layout = Layout(name: "Test Layout")
        room.layouts.append(layout)

        let controller = RoomSceneController(room: room, layout: layout)
        await controller.load()

        let bounds = try #require(controller.roomHorizontalBounds)
        // In Room-2.usdz, the room is normalized squarely at (0, 0) with floor at 0.0
        // Symmetrical interior drywall limits: X ~ [-2.02, 2.02], Z ~ [-2.11, 2.11]
        #expect(controller.floorLevel == 0.0)
        #expect(abs(bounds.minX + bounds.maxX) < 0.1)
        #expect(abs(bounds.minZ + bounds.maxZ) < 0.1)
        #expect(bounds.minX < -1.80)
        #expect(bounds.maxX > 1.80)
        #expect(bounds.minZ < -1.90)
        #expect(bounds.maxZ > 1.90)
    }

    @Test @MainActor func initialFurnitureInRoomTwoIsCenteredAndNonColliding() async throws {
        let container = try ModelContainer.createInMemoryContainer()
        let vm = DashboardViewModel()
        let room = vm.ensureRoom2Seeded(context: container.mainContext)
        let layout = try #require(room.layouts.first)

        #expect(layout.furnitures.count == 5)
        for item in layout.furnitures {
            #expect(item.positionY == 0.0)
        }

        // Test clearance engine detects zero overlaps between initial pieces
        for i in 0..<layout.furnitures.count {
            for j in (i + 1)..<layout.furnitures.count {
                let f1 = layout.furnitures[i]
                let f2 = layout.furnitures[j]
                let proxyA = FurnitureCollisionProxy(
                    id: f1.id,
                    category: f1.category,
                    position: SIMD3<Float>(f1.positionX, f1.positionY, f1.positionZ),
                    dimensions: SIMD3<Float>(f1.width, f1.height, f1.length),
                    rotationYaw: f1.rotationYaw
                )
                let proxyB = FurnitureCollisionProxy(
                    id: f2.id,
                    category: f2.category,
                    position: SIMD3<Float>(f2.positionX, f2.positionY, f2.positionZ),
                    dimensions: SIMD3<Float>(f2.width, f2.height, f2.length),
                    rotationYaw: f2.rotationYaw
                )
                let colliding = SpatialClearanceEngine.checkCollision(itemA: proxyA, itemB: proxyB)
                #expect(!colliding, "Expected no collision between \(f1.name) and \(f2.name)")
            }
        }
    }
}
