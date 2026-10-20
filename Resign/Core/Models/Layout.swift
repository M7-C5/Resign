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
}
