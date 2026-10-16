//
//  ModelContainer+Testing.swift
//  Resign
//

import Foundation
import SwiftData

extension ModelContainer {
    @MainActor
    public static func createInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            ScannedRoom.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
