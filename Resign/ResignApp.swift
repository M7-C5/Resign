//
//  ResignApp.swift
//  Resign
//

import SwiftUI
import SwiftData

@main
struct ResignApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Room.self,
            RoomOpening.self,
            Layout.self,
            Furniture.self,
            Light.self,
            Insight.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Room>()
        if let count = try? context.fetchCount(descriptor), count == 0 {
            if let mock = try? RoomRepository.loadMockRoomFromUSDZ() {
                context.insert(mock)
                try? context.save()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(sharedModelContainer)
    }
}
