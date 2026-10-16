//
//  ModelContainer+Testing.swift
//  Resign
//
//  Created by Agentic Workflow.
//

import Foundation
import SwiftData

extension ModelContainer {
    /// Creates an in-memory ModelContainer suitable for unit tests and SwiftUI Previews.
    @MainActor
    static func createInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Item.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
