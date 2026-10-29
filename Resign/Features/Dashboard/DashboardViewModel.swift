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
    public static let room2Name = "Room-2"

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

    @discardableResult
    public func ensureRoom2Seeded(context: ModelContext) -> Room {
        let targetName = Self.room2Name
        let descriptor = FetchDescriptor<Room>(
            predicate: #Predicate<Room> { $0.name == targetName || $0.name == "Room-2 (Studio)" }
        )
        if let existing = try? context.fetch(descriptor).first {
            if existing.layouts.isEmpty {
                let layout = Layout(
                    name: "Original Layout",
                    usdzURL: Bundle.main.url(forResource: "Room-2", withExtension: "usdz")
                )
                existing.layouts.append(layout)
                context.insert(layout)
                populateInitialFurniture(in: layout, context: context)
                try? context.save()
            } else if let layout = existing.layouts.first, layout.furnitures.isEmpty {
                populateInitialFurniture(in: layout, context: context)
                try? context.save()
            } else if let layout = existing.layouts.first {
                // Migrate legacy uncentered/slanted furniture (floorY ≈ -1.218) to centered coordinates
                if layout.furnitures.contains(where: { $0.positionY < -0.5 }) {
                    for item in layout.furnitures {
                        context.delete(item)
                    }
                    layout.furnitures.removeAll()
                    populateInitialFurniture(in: layout, context: context)
                    try? context.save()
                }
            }
            return existing
        }

        let room = Room(
            name: targetName,
            compass: 0.0,
            length: 4.88,
            width: 3.96,
            height: 2.6
        )
        context.insert(room)

        let layout = Layout(
            name: "Original Layout",
            usdzURL: Bundle.main.url(forResource: "Room-2", withExtension: "usdz")
        )
        room.layouts.append(layout)
        context.insert(layout)

        populateInitialFurniture(in: layout, context: context)
        try? context.save()
        return room
    }

    private func populateInitialFurniture(in layout: Layout, context: ModelContext) {
        guard layout.furnitures.isEmpty else { return }
        let floorY: Float = 0.0
        let items = [
            Furniture(name: "Queen Bed", category: "bed", positionX: -0.75, positionY: floorY, positionZ: -0.65, rotationYaw: 0, length: 2.0, width: 1.6, height: 0.9),
            Furniture(name: "Work Desk", category: "desk", positionX: 1.30, positionY: floorY, positionZ: 0.0, rotationYaw: 0, length: 1.4, width: 0.7, height: 0.75),
            Furniture(name: "Desk Chair", category: "chair", positionX: 0.60, positionY: floorY, positionZ: 0.0, rotationYaw: -.pi / 2, length: 0.6, width: 0.6, height: 0.9),
            Furniture(name: "Sofa", category: "sofa", positionX: -0.30, positionY: floorY, positionZ: 1.30, rotationYaw: .pi / 2, length: 2.0, width: 0.85, height: 0.8),
            Furniture(name: "Wardrobe", category: "storage", positionX: 0.95, positionY: floorY, positionZ: -1.45, rotationYaw: .pi / 2, length: 1.2, width: 0.6, height: 2.0)
        ]
        for item in items {
            layout.furnitures.append(item)
            context.insert(item)
        }
    }
}
