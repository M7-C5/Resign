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

    @State private var activeRoomId: UUID? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let roomId = activeRoomId {
                    RoomScanResultView(roomId: roomId) {
                        activeRoomId = nil
                    }
                } else {
                    RoomScanView { savedRoomId in
                        activeRoomId = savedRoomId
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
