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
            ScannedRoom.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(sharedModelContainer)
    }
}
