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
        let longerSide = max(payload.roomLength, payload.roomWidth)
        let shorterSide = min(payload.roomLength, payload.roomWidth)
        let room = Room(
            name: roomName,
            longitude: 0.0,
            latitude: 0.0,
            compass: 0.0,
            length: longerSide,
            width: shorterSide,
            height: payload.roomHeight
        )
        let snapshot: RoomPlanSnapshot?
        if !payload.walls.isEmpty {
            let snap = RoomPlanSnapshot(walls: payload.walls, floorLevel: payload.floorLevel)
            snapshot = snap
            room.planSnapshotData = try? JSONEncoder().encode(snap)
        } else {
            snapshot = nil
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
            let posX: Float
            let posY: Float
            let posZ: Float
            let yaw: Float

            if let snapshot {
                let local = snapshot.localCoordinates(worldX: obj.position.x, worldZ: obj.position.z)
                posX = local.x
                posZ = local.y
                yaw = snapshot.localYaw(obj.rotationYaw)
                posY = max(0.0, obj.position.y - payload.floorLevel)
            } else {
                posX = obj.position.x
                posY = max(0.0, obj.position.y - payload.floorLevel)
                posZ = obj.position.z
                yaw = obj.rotationYaw
            }

            let furniture = Furniture(
                name: obj.name,
                category: obj.category,
                positionX: posX,
                positionY: posY,
                positionZ: posZ,
                rotationYaw: yaw,
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
