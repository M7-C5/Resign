//
//  Room.swift
//  Resign
//

import Foundation
import SwiftData

@Model
public final class Room {
    public var id: UUID = UUID()
    public var name: String = "Room"
    public var longitude: Double = 0.0
    public var latitude: Double = 0.0
    public var compass: Double = 0.0
    public var length: Float = 5.0
    public var width: Float = 4.2
    public var height: Float = 2.6
    /// Optional scan-local wall frame for accurately projecting the captured room in 2D.
    public var planSnapshotData: Data? = nil
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Layout.room)
    public var layouts: [Layout] = []

    @Relationship(deleteRule: .cascade, inverse: \RoomOpening.room)
    public var openings: [RoomOpening] = []

    public init(
        id: UUID = UUID(),
        name: String = "Room",
        longitude: Double = 0.0,
        latitude: Double = 0.0,
        compass: Double = 0.0,
        length: Float = 5.0,
        width: Float = 4.2,
        height: Float = 2.6,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.longitude = longitude
        self.latitude = latitude
        self.compass = compass
        self.length = length
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
