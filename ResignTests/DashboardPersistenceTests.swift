//
//  DashboardPersistenceTests.swift
//  ResignTests
//

import Testing
import Foundation
import SwiftData
@testable import Resign

@Suite("Dashboard Persistence & ViewModel Tests")
struct DashboardPersistenceTests {

    @Test @MainActor func fetchEmptyStateInitially() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<Room>()
        let rooms = try context.fetch(descriptor)
        #expect(rooms.isEmpty)
    }

    @Test @MainActor func insertAndQueryRoom() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let room = Room(name: "Living Room")
        context.insert(room)
        try context.save()

        let descriptor = FetchDescriptor<Room>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let rooms = try context.fetch(descriptor)
        #expect(rooms.count == 1)
        #expect(rooms.first?.name == "Living Room")
    }

    @Test @MainActor func renameRoomTrimsWhitespaceAndUpdatesTimestamp() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = DashboardViewModel()

        let initialDate = Date(timeIntervalSince1970: 1000)
        let room = Room(name: "Old Bedroom", updatedAt: initialDate)
        context.insert(room)
        try context.save()

        viewModel.renameRoom(room, to: "   Modern Study   ", context: context)

        #expect(room.name == "Modern Study")
        #expect(room.updatedAt > initialDate)

        // Empty rename should be a no-op
        viewModel.renameRoom(room, to: "   ", context: context)
        #expect(room.name == "Modern Study")
    }

    @Test @MainActor func deleteRoomCascadesLayoutsAndOpenings() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = DashboardViewModel()

        let room = Room(name: "Master Suite")
        let layout = Layout(name: "Original")
        let opening = RoomOpening(type: "window", posX: 1.0, posY: 1.0, posZ: 0.0, width: 1.0, height: 1.0)
        room.layouts.append(layout)
        room.openings.append(opening)
        context.insert(room)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Room>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Layout>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<RoomOpening>()).count == 1)

        viewModel.deleteRoom(room, context: context)

        #expect(try context.fetch(FetchDescriptor<Room>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Layout>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RoomOpening>()).isEmpty)
    }

    @Test @MainActor func createAndRemoveLayoutInRoom() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = DashboardViewModel()

        let room = Room(name: "Guest Room")
        context.insert(room)
        try context.save()

        let createdLayout = viewModel.createLayout(named: "Cozy Nook", in: room, context: context)
        #expect(createdLayout.name == "Cozy Nook")
        #expect(room.layouts.count == 1)
        #expect(room.layouts.first?.id == createdLayout.id)

        viewModel.deleteLayout(createdLayout, from: room, context: context)
        #expect(room.layouts.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Layout>()).isEmpty)
    }

    @Test @MainActor func roomsAreSortedByUpdatedAt() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let olderRoom = Room(name: "Older Room", updatedAt: Date(timeIntervalSince1970: 1000))
        let newerRoom = Room(name: "Newer Room", updatedAt: Date(timeIntervalSince1970: 2000))
        context.insert(olderRoom)
        context.insert(newerRoom)
        try context.save()

        let descriptor = FetchDescriptor<Room>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 2)
        #expect(fetched.first?.name == "Newer Room")
        #expect(fetched.last?.name == "Older Room")
    }

    @Test @MainActor func ensureRoom2SeededCreatesRoomWithLayoutAndFurniture() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = DashboardViewModel()

        let room = viewModel.ensureRoom2Seeded(context: context)
        #expect(room.name == "Room-2")
        #expect(room.layouts.count == 1)

        let layout = try #require(room.layouts.first)
        #expect(layout.name == "Original Layout")
        #expect(layout.furnitures.count == 5)

        // Verify furniture types and positions
        let names = Set(layout.furnitures.map(\.name))
        #expect(names.contains("Queen Bed"))
        #expect(names.contains("Work Desk"))
        #expect(names.contains("Desk Chair"))
        #expect(names.contains("Sofa"))
        #expect(names.contains("Wardrobe"))
    }

    @Test @MainActor func ensureRoom2SeededIsIdempotent() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = DashboardViewModel()

        let room1 = viewModel.ensureRoom2Seeded(context: context)
        let room2 = viewModel.ensureRoom2Seeded(context: context)

        #expect(room1.id == room2.id)
        let allRooms = try context.fetch(FetchDescriptor<Room>())
        #expect(allRooms.count == 1)
        #expect(room2.layouts.first?.furnitures.count == 5)
    }

    @Test @MainActor func resolvedUSDZURLRebindsAfterSandboxContainerRelocationAndDeletesRoomDirectory() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = DashboardViewModel()

        let room = Room(name: "Relocated Scan Room")
        let layout = Layout(name: "Original Scan")
        // Simulate a stale sandbox container UUID path from a previous app install/build
        layout.usdzURL = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/OLD-SANDBOX-UUID/Documents/Rooms/\(room.id)/Room.usdz")
        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let roomDir = docsDir.appendingPathComponent("Rooms/\(room.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)
        let liveFileURL = roomDir.appendingPathComponent("Room.usdz")
        try Data("mock-usdz".utf8).write(to: liveFileURL)

        // resolvedUSDZURL must dynamically locate the file in the current container's Documents directory
        let resolved = try #require(layout.resolvedUSDZURL)
        #expect(resolved.standardizedFileURL == liveFileURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: resolved.path))

        // Deleting the room must also remove its Rooms/<room.id> directory from disk
        viewModel.deleteRoom(room, context: context)
        #expect(!FileManager.default.fileExists(atPath: roomDir.path))
    }
}
