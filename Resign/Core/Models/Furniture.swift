//
//  Furniture.swift
//  Resign
//

import Foundation
import SwiftData

@Model
public final class Furniture {
    public var id: UUID = UUID()
    public var name: String = "Furniture"
    public var category: String = "other"      // "bed", "desk", "chair", "sofa", "closet", "television", etc.
    public var texture: String = "default"
    public var positionX: Float = 0
    public var positionY: Float = 0
    public var positionZ: Float = 0
    public var rotationYaw: Float = 0          // Radians around Y-axis
    public var length: Float = 1.0
    public var width: Float = 1.0
    public var height: Float = 1.0
    public var isArchived: Bool = false
    public var usdzURL: URL? = nil

    public var layout: Layout?

    public init(
        id: UUID = UUID(),
        name: String = "Furniture",
        category: String = "other",
        texture: String = "default",
        positionX: Float = 0,
        positionY: Float = 0,
        positionZ: Float = 0,
        rotationYaw: Float = 0,
        length: Float = 1.0,
        width: Float = 1.0,
        height: Float = 1.0,
        isArchived: Bool = false,
        usdzURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.texture = texture
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.rotationYaw = rotationYaw
        self.length = length
        self.width = width
        self.height = height
        self.isArchived = isArchived
        self.usdzURL = usdzURL
    }
}
