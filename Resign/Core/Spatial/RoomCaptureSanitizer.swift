//
//  RoomCaptureSanitizer.swift
//  Resign
//

import Foundation
import simd

public struct SanitizedObject: Sendable {
    public let name: String
    public let category: String
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float>
    public let rotationYaw: Float
    public let uniformScale: Float

    public init(
        name: String,
        category: String,
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        rotationYaw: Float,
        uniformScale: Float
    ) {
        self.name = name
        self.category = category
        self.position = position
        self.dimensions = dimensions
        self.rotationYaw = rotationYaw
        self.uniformScale = uniformScale
    }
}

public final class RoomCaptureSanitizer: Sendable {

    private let discardedCategories: Set<String> = [
        "bathtub",
        "toilet",
        "sink",
        "refrigerator",
        "stove",
        "oven",
        "dishwasher",
        "washerdryer",
        "stairs"
    ]

    private let masterAssetWidths: [String: Float] = [
        "bed": 1.6,
        "sofa": 2.1,
        "desk": 1.2,
        "table": 1.6,
        "chair": 0.65,
        "closet": 1.2,
        "television": 1.3,
        "fireplace": 1.2
    ]

    public init() {}

    public func sanitize(
        objects: [ScannedObjectPayload],
        roomWidth: Float,
        roomLength: Float,
        walls: [ScannedWallPayload] = [],
        floorLevel: Float = 0.0
    ) -> [SanitizedObject] {
        var result: [SanitizedObject] = []

        for obj in objects {
            let normalized = obj.rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // Discard bathroom fixtures & heavy appliances
            if discardedCategories.contains(normalized) {
                continue
            }

            // Map to living homeowner category
            guard let category = mapCategory(raw: normalized, dimensions: obj.dimensions) else {
                continue
            }

            // Grounding: Sit flush on the captured floor plane
            var groundedPos = obj.position
            groundedPos.y = floorLevel

            // Wall alignment snapping: use multi-wall segments if available, else bounding box
            let snapped: (pos: SIMD3<Float>, yaw: Float)
            if !walls.isEmpty {
                snapped = snapToWallSegments(
                    position: groundedPos,
                    dimensions: obj.dimensions,
                    yaw: obj.rotationYaw,
                    walls: walls
                )
            } else {
                let p = snapToRectangularWalls(
                    position: groundedPos,
                    dimensions: obj.dimensions,
                    roomWidth: roomWidth,
                    roomLength: roomLength
                )
                snapped = (pos: p, yaw: obj.rotationYaw)
            }

            // Calculate uniform scale multiplier relative to master asset width
            let masterWidth = masterAssetWidths[category] ?? max(obj.dimensions.x, 0.1)
            let uniformScale = obj.dimensions.x / masterWidth

            let name = defaultName(for: category, dimensions: obj.dimensions)

            let sanitized = SanitizedObject(
                name: name,
                category: category,
                position: snapped.pos,
                dimensions: obj.dimensions,
                rotationYaw: snapped.yaw,
                uniformScale: uniformScale
            )

            result.append(sanitized)
        }

        return result
    }

    private func mapCategory(raw: String, dimensions: SIMD3<Float>) -> String? {
        switch raw {
        case "bed":
            return "bed"
        case "sofa":
            return "sofa"
        case "chair":
            return "chair"
        case "storage":
            return "closet"
        case "television":
            return "television"
        case "fireplace":
            return "fireplace"
        case "table":
            // Distinguish desk vs dining/coffee table based on height & work surface proportions
            if dimensions.y <= 0.80 && (dimensions.x <= 1.85 && dimensions.z <= 0.95 || dimensions.z <= 1.85 && dimensions.x <= 0.95) {
                return "desk"
            }
            return "table"
        default:
            return nil
        }
    }

    private func snapToWallSegments(
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        yaw: Float,
        walls: [ScannedWallPayload]
    ) -> (pos: SIMD3<Float>, yaw: Float) {
        let snapThreshold: Float = 0.15
        let p2D = SIMD2<Float>(position.x, position.z)

        var closestWall: ScannedWallPayload?
        var minDistance: Float = .greatestFiniteMagnitude
        var bestProjected: SIMD2<Float> = p2D
        var bestNormal: SIMD2<Float> = .zero

        for wall in walls {
            let a = wall.startPoint
            let b = wall.endPoint
            let v = b - a
            let len = length(v)
            guard len > 0.05 else { continue }

            let vHat = v / len
            let normal = SIMD2<Float>(-vHat.y, vHat.x)

            let w = p2D - a
            let t = min(max(dot(w, vHat), 0.0), len)
            let projected = a + vHat * t
            let d = distance(p2D, projected)

            if d < minDistance {
                minDistance = d
                closestWall = wall
                bestProjected = projected
                bestNormal = normal
            }
        }

        guard let wall = closestWall else {
            return (position, yaw)
        }

        // Half wall thickness (centerline to inner drywall surface)
        let halfWallThickness = max(wall.dimensions.z, 0.10) / 2.0

        // True object extent along wall normal taking relative orientation into account
        let relYaw = yaw - wall.rotationYaw
        let cosRel = abs(cos(relYaw))
        let sinRel = abs(sin(relYaw))
        let halfObjDepth = (sinRel * dimensions.x + cosRel * dimensions.z) * 0.5

        let gap = minDistance - (halfWallThickness + halfObjDepth)

        if abs(gap) < snapThreshold {
            let dir = p2D - bestProjected
            let dirLen = length(dir)
            let outNormal = dirLen > 1e-4 ? (dir / dirLen) : bestNormal

            // Snap flush with inner plaster face: centerline + (T/2 + halfDepth)
            let totalOffset = halfWallThickness + halfObjDepth
            let snapped2D = bestProjected + outNormal * totalOffset
            let snappedPos = SIMD3<Float>(snapped2D.x, position.y, snapped2D.y)

            // Snap yaw to nearest orthogonal angle (parallel or perpendicular)
            var snappedYaw = yaw
            let quarterTurn = Float.pi * 0.5
            let k = round(relYaw / quarterTurn)
            if abs(relYaw - k * quarterTurn) < 0.26 {
                snappedYaw = wall.rotationYaw + k * quarterTurn
            }

            return (snappedPos, snappedYaw)
        }

        return (position, yaw)
    }

    private func snapToRectangularWalls(
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        roomWidth: Float,
        roomLength: Float,
        wallThickness: Float = 0.10
    ) -> SIMD3<Float> {
        var pos = position
        let snapThreshold: Float = 0.15

        let halfWallT = wallThickness / 2.0
        let innerHalfW = roomWidth / 2.0 - halfWallT
        let innerHalfL = roomLength / 2.0 - halfWallT

        let halfObjX = dimensions.x / 2.0
        let halfObjZ = dimensions.z / 2.0

        if abs((pos.x - halfObjX) - (-innerHalfW)) < snapThreshold {
            pos.x = -innerHalfW + halfObjX
        }
        if abs((pos.x + halfObjX) - innerHalfW) < snapThreshold {
            pos.x = innerHalfW - halfObjX
        }
        if abs((pos.z - halfObjZ) - (-innerHalfL)) < snapThreshold {
            pos.z = -innerHalfL + halfObjZ
        }
        if abs((pos.z + halfObjZ) - innerHalfL) < snapThreshold {
            pos.z = innerHalfL - halfObjZ
        }

        return pos
    }

    private func defaultName(for category: String, dimensions: SIMD3<Float>) -> String {
        switch category {
        case "bed":
            if dimensions.x <= 1.25 {
                return "Twin Bed"
            } else if dimensions.x <= 1.75 {
                return "Queen Bed"
            } else {
                return "King Bed"
            }
        case "sofa":
            if dimensions.x <= 1.75 {
                return "2-Seat Sofa"
            } else {
                return "3-Seat Sofa"
            }
        case "desk":
            if dimensions.x <= 1.25 {
                return "Compact Desk"
            } else {
                return "Work Desk"
            }
        case "table":
            if dimensions.y < 0.55 {
                return "Coffee Table"
            } else {
                return "Dining Table"
            }
        case "chair":
            return "Chair"
        case "closet":
            return "Wardrobe"
        case "television":
            return "TV Console"
        case "fireplace":
            return "Fireplace"
        default:
            return "Furniture"
        }
    }
}
