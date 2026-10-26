//
//  RoomCapturePayload.swift
//  Resign
//

import Foundation
import simd

public struct ScannedWallPayload: Sendable, Equatable {
    public let id: UUID
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float> // x: length, y: height, z: thickness
    public let rotationYaw: Float
    public let transform: simd_float4x4

    public init(
        id: UUID = UUID(),
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        rotationYaw: Float,
        transform: simd_float4x4 = matrix_identity_float4x4
    ) {
        self.id = id
        self.position = position
        self.dimensions = dimensions
        self.rotationYaw = rotationYaw
        self.transform = transform
    }

    /// Endpoints of the wall segment base at Y = 0 in world coordinates
    public var startPoint: SIMD2<Float> {
        let halfL = dimensions.x / 2.0
        let cosY = cos(rotationYaw)
        let sinY = sin(rotationYaw)
        return SIMD2<Float>(
            position.x - halfL * cosY,
            position.z + halfL * sinY
        )
    }

    public var endPoint: SIMD2<Float> {
        let halfL = dimensions.x / 2.0
        let cosY = cos(rotationYaw)
        let sinY = sin(rotationYaw)
        return SIMD2<Float>(
            position.x + halfL * cosY,
            position.z - halfL * sinY
        )
    }
}

public struct ScannedOpeningPayload: Sendable {
    public let type: String          // "window", "door", "opening"
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float>

    public init(type: String, position: SIMD3<Float>, dimensions: SIMD3<Float>) {
        self.type = type
        self.position = position
        self.dimensions = dimensions
    }
}

public struct ScannedObjectPayload: Sendable {
    public let rawCategory: String
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float>
    public let rotationYaw: Float

    public init(
        rawCategory: String,
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        rotationYaw: Float
    ) {
        self.rawCategory = rawCategory
        self.position = position
        self.dimensions = dimensions
        self.rotationYaw = rotationYaw
    }
}

public struct CapturedRoomPayload: Sendable {
    public let roomLength: Float     // Extent along Z
    public let roomWidth: Float      // Extent along X
    public let roomHeight: Float     // Extent along Y
    public let floorLevel: Float     // Y coordinate of floor plane in capture space
    public let walls: [ScannedWallPayload]
    public let openings: [ScannedOpeningPayload]
    public let objects: [ScannedObjectPayload]

    public init(
        roomLength: Float,
        roomWidth: Float,
        roomHeight: Float,
        floorLevel: Float = 0.0,
        walls: [ScannedWallPayload] = [],
        openings: [ScannedOpeningPayload],
        objects: [ScannedObjectPayload]
    ) {
        self.roomLength = roomLength
        self.roomWidth = roomWidth
        self.roomHeight = roomHeight
        self.floorLevel = floorLevel
        self.walls = walls
        self.openings = openings
        self.objects = objects
    }
}
