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

/// Scan-local projection data used to draw the captured room in a stable 2D plan.
public struct RoomPlanSnapshot: Codable, Sendable, Hashable {
    public struct WallSegment: Codable, Sendable, Hashable {
        public let startX: Float
        public let startZ: Float
        public let endX: Float
        public let endZ: Float

        public init(startX: Float, startZ: Float, endX: Float, endZ: Float) {
            self.startX = startX
            self.startZ = startZ
            self.endX = endX
            self.endZ = endZ
        }
    }

    public let centerX: Float
    public let centerZ: Float
    public let yawRadians: Float
    public let floorLevel: Float?
    public let wallSegments: [WallSegment]

    public init(walls: [ScannedWallPayload], floorLevel: Float? = nil) {
        self.floorLevel = floorLevel
        guard let primaryWall = walls.max(by: { $0.dimensions.x < $1.dimensions.x }) else {
            centerX = 0
            centerZ = 0
            yawRadians = 0
            wallSegments = []
            return
        }

        let yaw = primaryWall.rotationYaw
        let cosine = cos(yaw)
        let sine = sin(yaw)
        let axisX = SIMD2<Float>(cosine, -sine)
        let axisZ = SIMD2<Float>(sine, cosine)
        let wallCenters = walls.map { SIMD2<Float>($0.position.x, $0.position.z) }
        let xProjections = wallCenters.map { $0.x * axisX.x + $0.y * axisX.y }
        let zProjections = wallCenters.map { $0.x * axisZ.x + $0.y * axisZ.y }

        let centerAlongX = ((xProjections.min() ?? 0) + (xProjections.max() ?? 0)) / 2
        let centerAlongZ = ((zProjections.min() ?? 0) + (zProjections.max() ?? 0)) / 2
        let worldCenterX = axisX.x * centerAlongX + axisZ.x * centerAlongZ
        let worldCenterZ = axisX.y * centerAlongX + axisZ.y * centerAlongZ

        centerX = worldCenterX
        centerZ = worldCenterZ
        yawRadians = yaw
        wallSegments = walls.map { wall in
            let start = Self.localPoint(
                wall.startPoint,
                centerX: worldCenterX,
                centerZ: worldCenterZ,
                cosine: cosine,
                sine: sine
            )
            let end = Self.localPoint(
                wall.endPoint,
                centerX: worldCenterX,
                centerZ: worldCenterZ,
                cosine: cosine,
                sine: sine
            )
            return WallSegment(startX: start.x, startZ: start.y, endX: end.x, endZ: end.y)
        }
    }

    public func localCoordinates(worldX: Float, worldZ: Float) -> SIMD2<Float> {
        Self.localPoint(
            SIMD2<Float>(worldX, worldZ),
            centerX: centerX,
            centerZ: centerZ,
            cosine: cos(yawRadians),
            sine: sin(yawRadians)
        )
    }

    public func localYaw(_ worldYaw: Float) -> Float {
        worldYaw - yawRadians
    }

    private static func localPoint(
        _ point: SIMD2<Float>,
        centerX: Float,
        centerZ: Float,
        cosine: Float,
        sine: Float
    ) -> SIMD2<Float> {
        let deltaX = point.x - centerX
        let deltaZ = point.y - centerZ
        return SIMD2<Float>(
            deltaX * cosine - deltaZ * sine,
            deltaX * sine + deltaZ * cosine
        )
    }
}

/// Bounds in the normalized scan frame, shared by the plan and ceiling fixtures.
/// Summary room dimensions can be smaller than the scanned wall footprint.
struct RoomPlanBounds: Hashable, Sendable {
    let minX: Float
    let minZ: Float
    let width: Float
    let length: Float

    init(snapshot: RoomPlanSnapshot?, fallbackWidth: Float, fallbackLength: Float) {
        let walls = snapshot?.wallSegments ?? []
        let xs = walls.flatMap { [$0.startX, $0.endX] }.filter(\.isFinite)
        let zs = walls.flatMap { [$0.startZ, $0.endZ] }.filter(\.isFinite)
        if let x0 = xs.min(), let x1 = xs.max(), let z0 = zs.min(), let z1 = zs.max(),
           x1 - x0 > 0.5, z1 - z0 > 0.5 {
            minX = x0
            minZ = z0
            width = x1 - x0
            length = z1 - z0
        } else {
            width = max(0.5, fallbackWidth)
            length = max(0.5, fallbackLength)
            minX = -width / 2
            minZ = -length / 2
        }
    }

    func unitCoordinates(x: Float, z: Float) -> SIMD2<Float> {
        [(x - minX) / width, (z - minZ) / length]
    }

    func cellCenter(column: Float, row: Float) -> SIMD2<Float> {
        [minX + (min(4.5, max(-0.5, column)) + 0.5) / 5 * width,
         minZ + (min(4.5, max(-0.5, row)) + 0.5) / 5 * length]
    }
}
