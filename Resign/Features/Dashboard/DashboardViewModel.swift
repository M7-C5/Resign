//
//  DashboardViewModel.swift
//  Resign
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
public final class DashboardViewModel {
    public init() {}

    public func renameRoom(_ room: Room, to newName: String, context: ModelContext) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        room.name = trimmed
        room.updatedAt = Date()
        try? context.save()
    }

    public func deleteRoom(_ room: Room, context: ModelContext) {
        context.delete(room)
        try? context.save()
    }

    @discardableResult
    public func createLayout(named name: String, in room: Room, context: ModelContext) -> Layout {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let layoutName = trimmed.isEmpty ? "New Layout" : trimmed
        let layout = Layout(name: layoutName)
        room.layouts.append(layout)
        room.updatedAt = Date()
        try? context.save()
        return layout
    }

    public func deleteLayout(_ layout: Layout, from room: Room, context: ModelContext) {
        room.layouts.removeAll { $0.id == layout.id }
        context.delete(layout)
        room.updatedAt = Date()
        try? context.save()
    }
}
