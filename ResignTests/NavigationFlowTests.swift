//
//  NavigationFlowTests.swift
//  ResignTests
//

import Testing
import Foundation
import SwiftData
@testable import Resign

@Suite("Navigation Flow & Route Coordination Tests")
struct NavigationFlowTests {

    @Test func roomCreationRouteEqualityAndHashing() {
        let roomId1 = UUID()
        let roomId2 = UUID()
        let layoutId1 = UUID()

        let routeResult1 = RoomCreationRoute.result(roomId: roomId1)
        let routeResult1Copy = RoomCreationRoute.result(roomId: roomId1)
        let routeResult2 = RoomCreationRoute.result(roomId: roomId2)
        let routeOrientation = RoomCreationRoute.orientation(layoutID: layoutId1)
        let routeLighting = RoomCreationRoute.lightingSetup(layoutID: layoutId1)

        #expect(routeResult1 == routeResult1Copy)
        #expect(routeResult1 != routeResult2)
        #expect(routeResult1 != routeLighting)
        #expect(routeOrientation != routeLighting)

        let set: Set<RoomCreationRoute> = [routeResult1, routeResult1Copy, routeResult2, routeOrientation, routeLighting]
        #expect(set.count == 4)
    }

    @Test func navigationPathTransitions() {
        var path: [RoomCreationRoute] = []
        let roomId = UUID()
        let layoutId = UUID()

        // 1. Scanner finishes -> push result
        path.append(.result(roomId: roomId))
        #expect(path.count == 1)
        #expect(path.last == .result(roomId: roomId))

        // 2. Review advances to north alignment for the scanned layout.
        path.append(.orientation(layoutID: layoutId))
        #expect(path.count == 2)
        #expect(path.last == .orientation(layoutID: layoutId))

        // 3. Saving north opens lighting for the same layout.
        path.append(.lightingSetup(layoutID: layoutId))
        #expect(path.count == 3)
        #expect(path.last == .lightingSetup(layoutID: layoutId))

        // 4. Back from lighting returns to orientation, then scan review.
        path.removeLast()
        #expect(path.count == 2)
        #expect(path.last == .orientation(layoutID: layoutId))
        path.removeLast()
        #expect(path.count == 1)
        #expect(path.last == .result(roomId: roomId))

        // 5. User scans again -> resets stack to root
        path.removeAll()
        #expect(path.isEmpty)
    }

    @Test @MainActor func layoutRetrievalByUUIDForLightingContainer() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let room = Room(name: "Studio Room")
        let layout = Layout(name: "Default Layout")
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let targetId = layout.id
        let descriptor = FetchDescriptor<Layout>(predicate: #Predicate<Layout> { $0.id == targetId })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Default Layout")
        #expect(fetched.first?.id == targetId)
    }

    #if DEBUG
    @Test @MainActor func loadMockRoomPopulatesHierarchyAndCompletesState() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = RoomScanViewModel()

        let roomId = viewModel.loadMockRoom(modelContext: context)

        #expect(viewModel.state == .completed(roomId: roomId))

        let descriptor = FetchDescriptor<Room>(predicate: #Predicate<Room> { $0.id == roomId })
        let rooms = try context.fetch(descriptor)

        #expect(rooms.count == 1)
        let room = rooms.first!
        #expect(room.name == "Master Bedroom")
        #expect(!room.layouts.isEmpty)
        #expect(room.layouts.first?.furnitures.count == 6)
        #expect(room.openings.count == 2)
    }

    @Test @MainActor func viewModelResetRestoresScanState() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = RoomScanViewModel()

        let roomId = viewModel.loadMockRoom(modelContext: context)
        #expect(viewModel.state == .completed(roomId: roomId))

        viewModel.reset()
        if viewModel.isSupported {
            #expect(viewModel.state == .ready)
        } else {
            #expect(viewModel.state == .unsupported)
        }
        #expect(!viewModel.isCancelled)
        #expect(!viewModel.isShowingConfirmationAlert)
    }
    #endif
}
