//
//  SolverTestSupport.swift
//  ResignTests
//
//  Shared room fixtures for solver / validator tests. All furniture follows the same
//  yaw-0 mesh convention as MockRoom.usdz and USDZRoomLoader.
//

import Foundation
@testable import Resign

@MainActor
enum SolverFixtures {
    struct Opening {
        var x: Float
        var z: Float
        var width: Float
    }

    static func room(
        width: Float,
        length: Float,
        door: Opening,
        window: Opening
    ) -> Room {
        let room = Room(length: length, width: width, height: 2.6)
        room.openings = [
            RoomOpening(type: "door", posX: door.x, posY: 0.0, posZ: door.z, width: door.width, height: 2.1),
            RoomOpening(type: "window", posX: window.x, posY: 1.45, posZ: window.z, width: window.width, height: 1.2)
        ]
        return room
    }

    /// Fresh copies of the six reference pieces (bed, desk, chair, sofa, wardrobe, TV) plus an entry stool.
    static func baseLayout() -> Layout {
        let standard = RoomRepository.createStandardMockRoom().layouts.first!
        var items = standard.furnitures.map { item in
            Furniture(
                name: item.name,
                category: item.category,
                texture: item.texture,
                positionX: item.positionX,
                positionY: item.positionY,
                positionZ: item.positionZ,
                rotationYaw: item.rotationYaw,
                length: item.length,
                width: item.width,
                height: item.height
            )
        }
        items.append(
            Furniture(
                name: "Entry Stool",
                category: "chair",
                positionX: 0, positionY: 0.25, positionZ: 0,
                length: 0.45, width: 0.45, height: 0.5
            )
        )
        let layout = Layout(name: "Base")
        layout.furnitures = items
        return layout
    }

    /// Rooms with different sizes and different door / window walls.
    static var variedRooms: [(name: String, room: Room)] {
        [
            ("standard 5.0x4.2 door S window E", RoomRepository.createStandardMockRoom()),
            ("wide 6.0x4.5 door W window N", room(
                width: 6.0, length: 4.5,
                door: Opening(x: -3.0, z: 0.6, width: 0.9),
                window: Opening(x: 0.5, z: -2.25, width: 1.6))),
            ("large 7.0x5.0 door S window E", room(
                width: 7.0, length: 5.0,
                door: Opening(x: -2.5, z: 2.5, width: 1.0),
                window: Opening(x: 3.5, z: 0.0, width: 2.0))),
            ("mid 5.5x4.6 door N window W", room(
                width: 5.5, length: 4.6,
                door: Opening(x: -1.8, z: -2.3, width: 0.9),
                window: Opening(x: -2.75, z: 0.2, width: 1.4)))
        ]
    }
}
