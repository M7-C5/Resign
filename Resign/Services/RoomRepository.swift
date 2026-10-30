//
//  RoomRepository.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation

public final class RoomRepository {
    public init() {}

    /// Dynamically loads and extracts the real 3D room, openings, and furniture directly from `MockRoom.usdz` via ModelIO.
    @MainActor
    public static func loadMockRoomFromUSDZ() throws -> Room {
        guard let url = USDZRoomLoader.findBundledMockRoomURL() else {
            throw USDZRoomLoaderError.fileNotFound("MockRoom.usdz")
        }
        return try USDZRoomLoader().loadRoom(from: url)
    }

    /// Creates the standard 5.0m x 4.2m reference room matching `MockRoom.usdz`.
    public static func createStandardMockRoom() -> Room {
        let room = Room(
            name: "Standard Reference Room",
            longitude: -122.4194,
            latitude: 37.7749,
            compass: 90.0,
            length: 4.2,
            width: 5.0,
            height: 2.6
        )

        let window = RoomOpening(type: "window", posX: 2.5, posY: 1.45, posZ: 0.0, width: 1.6, height: 1.2)
        let door = RoomOpening(type: "door", posX: -1.5, posY: 0.0, posZ: 2.1, width: 0.9, height: 2.1)
        room.openings = [window, door]

        let layout = Layout(name: "Initial Arrangement")

        let bed = Furniture(
            name: "Queen Bed",
            category: "bed",
            texture: "oak_fabric",
            positionX: -1.3,
            positionY: 0.5,
            positionZ: -1.0,
            rotationYaw: 0,
            length: 2.0,
            width: 1.6,
            height: 1.0
        )

        let desk = Furniture(
            name: "Work Desk",
            category: "desk",
            texture: "metal_wood",
            positionX: 2.125,
            positionY: 0.375,
            positionZ: -1.2,
            rotationYaw: 0,
            length: 1.2,
            width: 0.65,
            height: 0.75
        )

        let chair = Furniture(
            name: "Office Chair",
            category: "chair",
            texture: "charcoal_mesh",
            positionX: 1.42,
            positionY: 0.45,
            positionZ: -1.2,
            rotationYaw: 0,
            length: 0.44,
            width: 0.44,
            height: 0.9
        )

        let sofa = Furniture(
            name: "Slate Sofa",
            category: "sofa",
            texture: "slate_fabric",
            positionX: 1.2,
            positionY: 0.41,
            positionZ: 1.075,
            rotationYaw: 0,
            length: 0.85,
            width: 2.0,
            height: 0.82
        )

        let closet = Furniture(
            name: "Wardrobe",
            category: "closet",
            texture: "ash_brass",
            positionX: -2.18,
            positionY: 1.05,
            positionZ: 1.2,
            rotationYaw: 0,
            length: 1.2,
            width: 0.6,
            height: 2.1
        )

        let tv = Furniture(
            name: "TV & Console",
            category: "television",
            texture: "walnut_black",
            positionX: 0.95,
            positionY: 0.28,
            positionZ: -1.83,
            rotationYaw: 0,
            length: 0.38,
            width: 1.4,
            height: 0.56
        )

        layout.furnitures = [bed, desk, chair, sofa, closet, tv]
        room.layouts = [layout]

        return room
    }

    /// Creates a mock room intentionally seeded with Panero & Zelnik clearance violations:
    /// standard room baseline (bed-closet R1 and bed-left R4) plus an Entry Stool obstructing the door swing (R6).
    public static func createViolatingMockRoom() -> Room {
        let room = createStandardMockRoom()
        guard let layout = room.layouts.first else { return room }

        // Move stool right into the door swing path at South wall (X: -1.5, Z: 1.65) -> R6
        let obstructingChair = Furniture(
            name: "Entry Stool",
            category: "chair",
            texture: "wood_stool",
            positionX: -1.5,
            positionY: 0.25,
            positionZ: 1.65,
            rotationYaw: 0,
            length: 0.45,
            width: 0.45,
            height: 0.5
        )
        layout.furnitures.append(obstructingChair)

        return room
    }
}
