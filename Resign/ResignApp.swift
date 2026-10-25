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

    var body: some Scene {
        WindowGroup {
            RoomSimulationView(settings: LightingSimulationSettings(artificialLightsOn: ProcessInfo.processInfo.environment["PROBE_LIGHTS"] == "1", minuteOfDay: Int(ProcessInfo.processInfo.environment["PROBE_MINUTE"] ?? "480") ?? 480))
        }
        .modelContainer(sharedModelContainer)
    }
}
