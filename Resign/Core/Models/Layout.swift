//
//  Layout.swift
//  Resign
//

import Foundation
import SwiftData

@Model
public final class Layout {
    public var id: UUID = UUID()
    public var name: String = "Layout"
    public var usdzURL: URL? = nil
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var room: Room?

    @Relationship(deleteRule: .cascade, inverse: \Furniture.layout)
    public var furnitures: [Furniture] = []

    @Relationship(deleteRule: .cascade, inverse: \Light.layout)
    public var lights: [Light] = []

    @Relationship(deleteRule: .cascade, inverse: \Insight.layout)
    public var insights: [Insight] = []

    public init(
        id: UUID = UUID(),
        name: String = "Layout",
        usdzURL: URL? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.usdzURL = usdzURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Dynamically resolves the USDZ file URL across iOS sandbox container UUID relocations
    /// (e.g. after Xcode rebuilds or app updates) and bundle path changes.
    public var resolvedUSDZURL: URL? {
        let fm = FileManager.default
        if let url = usdzURL, fm.fileExists(atPath: url.path) {
            return url
        }

        let fileName = usdzURL?.lastPathComponent ?? "Room.usdz"

        // 1. Check current Documents/Rooms/<room.id>/<fileName>
        if let roomID = room?.id,
           let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docsDir
                .appendingPathComponent("Rooms/\(roomID)", isDirectory: true)
                .appendingPathComponent(fileName)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            let defaultRoomCandidate = docsDir
                .appendingPathComponent("Rooms/\(roomID)", isDirectory: true)
                .appendingPathComponent("Room.usdz")
            if fm.fileExists(atPath: defaultRoomCandidate.path) {
                return defaultRoomCandidate
            }
        }

        // 2. If usdzURL had a Rooms/<UUID>/<file> structure (even if self.room is not faulted)
        if let url = usdzURL,
           let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let components = url.pathComponents
            if let roomsIdx = components.lastIndex(of: "Rooms"), roomsIdx + 2 < components.count {
                let relativeComponents = components[roomsIdx...]
                var rebased = docsDir
                for part in relativeComponents {
                    rebased.appendPathComponent(part)
                }
                if fm.fileExists(atPath: rebased.path) {
                    return rebased
                }
            }

            // 3. Check if it was a bundled resource whose bundle container path changed
            let resourceName = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.isEmpty ? "usdz" : url.pathExtension
            if let bundled = Bundle.main.url(forResource: resourceName, withExtension: ext) {
                return bundled
            }
        }

        return usdzURL
    }
}
