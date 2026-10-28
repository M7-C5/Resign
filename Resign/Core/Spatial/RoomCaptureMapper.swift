//
//  RoomCaptureMapper.swift
//  Resign
//

import Foundation
import SwiftData

public final class RoomCaptureMapper: Sendable {

    private let sanitizer: RoomCaptureSanitizer

    public init(sanitizer: RoomCaptureSanitizer = RoomCaptureSanitizer()) {
        self.sanitizer = sanitizer
    }

    public func mapToRoom(payload: CapturedRoomPayload, roomName: String = "Scanned Room") -> Room {
        let room = Room(
            name: roomName,
            longitude: 0.0,
            latitude: 0.0,
            compass: 0.0,
            length: payload.roomLength,
            width: payload.roomWidth,
            height: payload.roomHeight
        )
        if !payload.walls.isEmpty {
            room.planSnapshotData = try? JSONEncoder().encode(RoomPlanSnapshot(walls: payload.walls, floorLevel: payload.floorLevel))
        }

        // Map window and door apertures
        for opening in payload.openings {
            let roomOpening = RoomOpening(
                type: opening.type,
                posX: opening.position.x,
                posY: opening.position.y,
                posZ: opening.position.z,
                width: opening.dimensions.x,
                height: opening.dimensions.y
            )
            room.openings.append(roomOpening)
        }

        // Sanitize and map detected furniture objects into the initial layout
        let sanitizedObjects = sanitizer.sanitize(
            objects: payload.objects,
            roomWidth: payload.roomWidth,
            roomLength: payload.roomLength,
            walls: payload.walls,
            floorLevel: payload.floorLevel
        )

        let layout = Layout(name: "Original Scan")
        for obj in sanitizedObjects {
            let furniture = Furniture(
                name: obj.name,
                category: obj.category,
                positionX: obj.position.x,
                positionY: obj.position.y,
                positionZ: obj.position.z,
                rotationYaw: obj.rotationYaw,
                length: obj.dimensions.z,
                width: obj.dimensions.x,
                height: obj.dimensions.y
            )
            layout.furnitures.append(furniture)
        }

        room.layouts.append(layout)
        return room
    }
}
