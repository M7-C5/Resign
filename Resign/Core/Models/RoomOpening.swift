//
//  RoomOpening.swift
//  Resign
//

import Foundation
import SwiftData

@Model
public final class RoomOpening {
    public var id: UUID = UUID()
    public var type: String = "window"          // "window", "door", "opening"
    public var posX: Float = 0
    public var posY: Float = 0
    public var posZ: Float = 0
    public var width: Float = 1.0
    public var height: Float = 1.2

    public var room: Room?

    public init(
        id: UUID = UUID(),
        type: String = "window",
        posX: Float = 0,
        posY: Float = 0,
        posZ: Float = 0,
        width: Float = 1.0,
        height: Float = 1.2
    ) {
        self.id = id
        self.type = type
        self.posX = posX
        self.posY = posY
        self.posZ = posZ
        self.width = width
        self.height = height
    }
}
