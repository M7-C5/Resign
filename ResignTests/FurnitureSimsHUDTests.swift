import Foundation
import Testing
import SwiftData
import simd
@testable import Resign

@Suite("Furniture Sims HUD interaction and rotation tests")
struct FurnitureSimsHUDTests {

    @Test @MainActor func stepRotation90CyclesCleanlyClockwise() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Test Room", length: 5.0, width: 4.0, height: 2.6)
        let layout = Layout(name: "Default")
        let desk = Furniture(
            name: "Study Desk",
            category: "desk",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            rotationYaw: 0.0,
            length: 1.4,
            width: 0.7,
            height: 0.75
        )
        layout.furnitures.append(desk)
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: desk.id, in: layout)

        // Step 1: 0 -> pi / 2
        let res1 = try #require(viewModel.rotateSelectedFurniture90(in: layout, context: context))
        #expect(abs(res1.yaw - (.pi / 2.0)) < 0.001)

        // Step 2: pi / 2 -> pi
        let res2 = try #require(viewModel.rotateSelectedFurniture90(in: layout, context: context))
        #expect(abs(abs(res2.yaw) - .pi) < 0.001)

        // Step 3: pi -> 3pi / 2 (SpatialClearanceEngine snaps to [0, 2pi))
        let res3 = try #require(viewModel.rotateSelectedFurniture90(in: layout, context: context))
        #expect(abs(res3.yaw - (3.0 * .pi / 2.0)) < 0.001)

        // Step 4: 3pi / 2 -> 0
        let res4 = try #require(viewModel.rotateSelectedFurniture90(in: layout, context: context))
        #expect(abs(res4.yaw) < 0.001)
    }

    @Test @MainActor func stepRotation45CyclesCleanlyClockwise() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Office", length: 5.0, width: 4.0, height: 2.6)
        let layout = Layout(name: "Default")
        let desk = Furniture(
            name: "Study Desk",
            category: "desk",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            rotationYaw: 0.0,
            length: 1.4,
            width: 0.7,
            height: 0.75
        )
        layout.furnitures.append(desk)
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: desk.id, in: layout)

        // 8 steps of 45 degrees clockwise around +Y
        let expectedAngles: [Float] = [
            7.0 * .pi / 4.0,
            3.0 * .pi / 2.0,
            5.0 * .pi / 4.0,
            .pi,
            3.0 * .pi / 4.0,
            .pi / 2.0,
            .pi / 4.0,
            0.0
        ]

        for expected in expectedAngles {
            let res = try #require(viewModel.rotateSelectedFurniture45(in: layout, context: context))
            if expected == 0.0 {
                #expect(abs(res.yaw) < 0.001)
            } else {
                #expect(abs(res.yaw - expected) < 0.001)
            }
        }
    }

    @Test @MainActor func continuousDragRotationSnapsToWallAngles() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Studio", length: 6.0, width: 5.0, height: 2.6)
        let layout = Layout(name: "Primary")
        let sofa = Furniture(
            name: "Sofa",
            category: "sofa",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            rotationYaw: 0.0,
            length: 2.0,
            width: 0.9,
            height: 0.8
        )
        layout.furnitures.append(sofa)
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: sofa.id, in: layout)

        // Drag to 1.52 radians (~87.1° - close to pi / 2 = 1.5708 rad) -> should snap to pi / 2
        let resSnap90 = try #require(viewModel.rotateSelectedFurniture(to: 1.52, in: layout, context: context, snapThreshold: 0.12))
        #expect(resSnap90.didSnap)
        #expect(abs(resSnap90.yaw - (.pi / 2.0)) < 0.001)

        // Drag to 0.76 radians (~43.5° - close to pi / 4 = 0.7854 rad) -> should snap to pi / 4
        let resSnap45 = try #require(viewModel.rotateSelectedFurniture(to: 0.76, in: layout, context: context, snapThreshold: 0.12))
        #expect(resSnap45.didSnap)
        #expect(abs(resSnap45.yaw - (.pi / 4.0)) < 0.001)

        // Drag to 0.38 radians (~21.8° - halfway between 0 and 45°) -> should NOT snap
        let resFree = try #require(viewModel.rotateSelectedFurniture(to: 0.38, in: layout, context: context, snapThreshold: 0.12))
        #expect(!resFree.didSnap)
        #expect(abs(resFree.yaw - 0.38) < 0.001)
    }

    @Test @MainActor func movementRequiresSelectedFurnitureID() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Studio", length: 6.0, width: 5.0, height: 2.6)
        let layout = Layout(name: "Primary")
        let sofa = Furniture(
            name: "Sofa",
            category: "sofa",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            rotationYaw: 0.0,
            length: 2.0,
            width: 0.9,
            height: 0.8
        )
        layout.furnitures.append(sofa)
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        // No selection made yet
        #expect(viewModel.selectedFurnitureID == nil)

        // Attempting to move without selection fails safely
        let moveResult = viewModel.moveSelectedFurniture(to: SIMD2<Float>(1.0, 1.0), in: layout, context: context)
        #expect(moveResult == nil)

        // Attempting to rotate without selection fails safely
        let rotResult = viewModel.rotateSelectedFurniture45(in: layout, context: context)
        #expect(rotResult == nil)
    }

    @Test func hudScreenPositionClampingAvoidsTopEdgeOverlap() {
        let screenSize = CGSize(width: 1024, height: 768)

        // Projected point near the very top of the screen (e.g. y = 30)
        let rawTopPoint = CGPoint(x: 500, y: 30)
        let clamped = FurnitureSimsActionHUD.clampedPosition(
            projected: rawTopPoint,
            in: screenSize,
            verticalOffset: 45
        )

        // Invariant: Must maintain safe margin from top bar (at least 60pt)
        #expect(clamped.y >= 60)
        #expect(clamped.x == 500)

        // Point near center of screen
        let rawCenterPoint = CGPoint(x: 512, y: 384)
        let clampedCenter = FurnitureSimsActionHUD.clampedPosition(
            projected: rawCenterPoint,
            in: screenSize,
            verticalOffset: 45
        )
        #expect(abs(clampedCenter.y - 339.0) < 0.001)
        #expect(abs(clampedCenter.x - 512.0) < 0.001)
    }

    @Test @MainActor func archivingDeselectsAndClearsProjection() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Guest", length: 4.0, width: 4.0, height: 2.6)
        let layout = Layout(name: "Scan")
        let chair = Furniture(
            name: "Accent Chair",
            category: "chair",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            rotationYaw: 0.0,
            length: 0.8,
            width: 0.8,
            height: 0.85
        )
        layout.furnitures.append(chair)
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: chair.id, in: layout)
        viewModel.selectedFurnitureScreenPosition = CGPoint(x: 400, y: 300)

        #expect(viewModel.selectedFurnitureID == chair.id)
        #expect(viewModel.selectedFurnitureScreenPosition != nil)

        // Archive the selected chair
        viewModel.archiveFurniture(id: chair.id, in: layout, context: context)

        // Invariant: Selection and screen position must be dismissed
        #expect(viewModel.selectedFurnitureID == nil)
        #expect(viewModel.selectedFurnitureScreenPosition == nil)
        #expect(chair.isArchived)
    }

    @Test func circularAngleDeltaTracksFull360ClockwiseAndCounterClockwise() {
        let center = CGPoint(x: 300, y: 300)
        let radius: CGFloat = 100
        let steps = 16

        // 1. Clockwise circle
        var accumulatedClockwise: Float = 0
        var prevCW: CGPoint = CGPoint(x: center.x + radius, y: center.y)
        for i in 1...steps {
            let angle = CGFloat(i) * (2.0 * .pi / CGFloat(steps))
            let curr = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let delta = SpatialClearanceEngine.circularAngleDelta(center: center, previous: prevCW, current: curr)
            accumulatedClockwise += delta
            prevCW = curr
        }
        #expect(abs(accumulatedClockwise - (2.0 * .pi)) < 0.001)

        // 2. Counter-Clockwise circle
        var accumulatedCCW: Float = 0
        var prevCCW: CGPoint = CGPoint(x: center.x + radius, y: center.y)
        for i in 1...steps {
            let angle = -CGFloat(i) * (2.0 * .pi / CGFloat(steps))
            let curr = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let delta = SpatialClearanceEngine.circularAngleDelta(center: center, previous: prevCCW, current: curr)
            accumulatedCCW += delta
            prevCCW = curr
        }
        #expect(abs(accumulatedCCW - (-2.0 * .pi)) < 0.001)
    }

    @Test func circularAngleDeltaHandlesBoundaryConditions() {
        let center = CGPoint(x: 200, y: 200)

        // Crossing negative X axis: (-100, -2) to (-100, 2)
        let p1 = CGPoint(x: center.x - 100, y: center.y - 2)
        let p2 = CGPoint(x: center.x - 100, y: center.y + 2)
        let delta = SpatialClearanceEngine.circularAngleDelta(center: center, previous: p1, current: p2)
        // Moving downwards on the left side is counter-clockwise (negative delta)
        #expect(delta < 0)
        #expect(abs(delta) < 0.1) // smooth, no singularity jump

        // Identity (no movement)
        let zeroDelta = SpatialClearanceEngine.circularAngleDelta(center: center, previous: p1, current: p1)
        #expect(zeroDelta == 0)

        // Point inside deadzone (< 4pt from center)
        let nearCenter = CGPoint(x: center.x + 1, y: center.y + 1)
        let deadzoneDelta = SpatialClearanceEngine.circularAngleDelta(center: center, previous: nearCenter, current: p1)
        #expect(deadzoneDelta == 0)
    }

    @Test @MainActor func continuousCircularRotationSnapsAtAll45DegreeIncrements() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Studio", length: 6.0, width: 5.0, height: 2.6)
        let layout = Layout(name: "Primary")
        let sofa = Furniture(
            name: "Sofa",
            category: "sofa",
            positionX: 0.0,
            positionY: 0.0,
            positionZ: 0.0,
            rotationYaw: 0.0,
            length: 2.0,
            width: 0.9,
            height: 0.8
        )
        layout.furnitures.append(sofa)
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        viewModel.selectFurniture(id: sofa.id, in: layout)

        // Test snapping at each 45° increment (0 through 7)
        for i in 0..<8 {
            let target = Float(i) * (.pi / 4.0)
            let slightlyOff = target + 0.04
            let result = try #require(viewModel.rotateSelectedFurniture(to: slightlyOff, in: layout, context: context, snapThreshold: 0.10))
            #expect(result.didSnap)
            #expect(abs(result.yaw - target) < 0.001)
        }
    }

    @Test @MainActor func saveCurrentLayoutUpdatesTimestamp() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Living Room", length: 6.0, width: 4.5, height: 2.6)
        let layout = Layout(name: "Original", createdAt: Date().addingTimeInterval(-3600), updatedAt: Date().addingTimeInterval(-3600))
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let originalTimestamp = layout.updatedAt
        let viewModel = Studio3DViewModel()
        viewModel.saveCurrentLayout(layout, context: context)

        #expect(layout.updatedAt > originalTimestamp)
    }

    @Test @MainActor func saveLayoutAsClonesFurnituresAndLightsDeeply() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Master Bedroom", length: 5.0, width: 4.0, height: 2.6)
        let sourceLayout = Layout(name: "Draft 1")
        let desk = Furniture(
            name: "Writing Desk",
            category: "desk",
            positionX: 1.2,
            positionY: 0.0,
            positionZ: -0.5,
            rotationYaw: .pi / 4.0,
            length: 1.2,
            width: 0.6,
            height: 0.75
        )
        let chair = Furniture(
            name: "Desk Chair",
            category: "chair",
            positionX: 1.2,
            positionY: 0.0,
            positionZ: 0.2,
            rotationYaw: 0.0,
            length: 0.6,
            width: 0.6,
            height: 0.85
        )
        let ceilingLight = Light(
            name: "Ceiling Chandelier",
            coordinateX: 2.5,
            coordinateY: 2.0,
            elevationZ: 2.5,
            brightness: 1200,
            colorTemp: 2700,
            isOn: true
        )
        desk.layout = sourceLayout
        chair.layout = sourceLayout
        ceilingLight.layout = sourceLayout
        sourceLayout.furnitures = [desk, chair]
        sourceLayout.lights = [ceilingLight]
        sourceLayout.room = room
        room.layouts.append(sourceLayout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        let newLayout = viewModel.saveLayoutAs(name: "Draft 2", from: sourceLayout, context: context)

        #expect(newLayout.name == "Draft 2")
        #expect(newLayout.room?.id == room.id)
        #expect(room.layouts.contains { $0.id == newLayout.id })
        #expect(newLayout.furnitures.count == 2)
        #expect(newLayout.lights.count == 1)

        // Verify deep copy: IDs must be distinct from source
        let clonedDesk = try #require(newLayout.furnitures.first { $0.name == "Writing Desk" })
        #expect(clonedDesk.id != desk.id)
        #expect(clonedDesk.positionX == desk.positionX)
        #expect(clonedDesk.positionZ == desk.positionZ)
        #expect(clonedDesk.rotationYaw == desk.rotationYaw)
        #expect(clonedDesk.layout?.id == newLayout.id)

        let clonedLight = try #require(newLayout.lights.first)
        #expect(clonedLight.id != ceilingLight.id)
        #expect(clonedLight.brightness == ceilingLight.brightness)
        #expect(clonedLight.colorTemp == ceilingLight.colorTemp)
        #expect(clonedLight.layout?.id == newLayout.id)
    }

    @Test @MainActor func saveLayoutAsUsesFallbackNameWhenBlank() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let room = Room(name: "Den", length: 4.0, width: 3.5, height: 2.6)
        let sourceLayout = Layout(name: "Minimalist")
        sourceLayout.room = room
        room.layouts.append(sourceLayout)
        context.insert(room)
        try context.save()

        let viewModel = Studio3DViewModel()
        let newLayout = viewModel.saveLayoutAs(name: "   \n  ", from: sourceLayout, context: context)

        #expect(newLayout.name == "Minimalist Copy")
    }
}
