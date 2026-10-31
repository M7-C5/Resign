//
//  SpatialClearanceEngine.swift
//  Resign
//

import Foundation
import simd

public struct FurnitureCollisionProxy: Sendable, Equatable {
    public let id: UUID
    public let category: String
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float> // x: width, y: height, z: length
    public let rotationYaw: Float

    public init(
        id: UUID = UUID(),
        category: String,
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        rotationYaw: Float
    ) {
        self.id = id
        self.category = category
        self.position = position
        self.dimensions = dimensions
        self.rotationYaw = rotationYaw
    }
}

public enum SpatialClearanceEngine {

    /// Clamps a furniture item's 2D floor position within explicit room bounding limits,
    /// correctly handling scanned rooms whose origin is offset from (0, 0) and non-rectangular
    /// floor plans with irregular grooves, alcoves, or L-shapes.
    public static func clampToRoomBoundaries(
        position: SIMD2<Float>,
        furnitureWidth: Float,
        furnitureLength: Float,
        rotationYaw: Float,
        minX: Float,
        maxX: Float,
        minZ: Float,
        maxZ: Float,
        walls: [RoomPlanSnapshot.WallSegment] = []
    ) -> SIMD2<Float> {
        let extentX = (abs(furnitureWidth * cos(rotationYaw)) + abs(furnitureLength * sin(rotationYaw))) * 0.5
        let extentZ = (abs(furnitureWidth * sin(rotationYaw)) + abs(furnitureLength * cos(rotationYaw))) * 0.5

        let validMinX = minX + extentX
        let validMaxX = maxX - extentX
        let validMinZ = minZ + extentZ
        let validMaxZ = maxZ - extentZ

        let clampedX = validMinX <= validMaxX ? min(max(position.x, validMinX), validMaxX) : (minX + maxX) * 0.5
        let clampedZ = validMinZ <= validMaxZ ? min(max(position.y, validMinZ), validMaxZ) : (minZ + maxZ) * 0.5
        let boxClamped = SIMD2<Float>(clampedX, clampedZ)

        guard let closedWalls = closeWallPolygon(walls) else {
            return boxClamped
        }

        // Polygon boundary projection: prevents furniture from penetrating exterior notches
        // while allowing free traversal into the tail of L-shaped spaces and deep alcoves.
        return projectIntoRoomPolygon(boxClamped, walls: closedWalls, margin: max(0.15, min(extentX, extentZ)))
    }

    /// Stitches small corner or doorway gaps (up to `maxGap` meters) between wall segments
    /// to form a watertight closed polygon loop. Returns `nil` if the segments represent an
    /// incomplete or open scan (< 3 walls or unbridgeable open perimeter).
    public static func closeWallPolygon(
        _ walls: [RoomPlanSnapshot.WallSegment],
        maxGap: Float = 1.25
    ) -> [RoomPlanSnapshot.WallSegment]? {
        let validWalls = walls.filter {
            let dx = $0.endX - $0.startX
            let dz = $0.endZ - $0.startZ
            return (dx * dx + dz * dz) > 1e-5
        }
        guard validWalls.count >= 3 else { return nil }

        let endpoints: [SIMD2<Float>] = validWalls.flatMap {
            [SIMD2<Float>($0.startX, $0.startZ), SIMD2<Float>($0.endX, $0.endZ)]
        }

        var pairs: [(u: Int, v: Int, distSq: Float)] = []
        let maxGapSq = maxGap * maxGap
        for u in 0..<endpoints.count {
            for v in (u + 1)..<endpoints.count where (u / 2) != (v / 2) {
                let dSq = simd_distance_squared(endpoints[u], endpoints[v])
                if dSq <= maxGapSq {
                    pairs.append((u, v, dSq))
                }
            }
        }
        pairs.sort { $0.distSq < $1.distSq }

        var matched = Set<Int>()
        var stitched = validWalls
        for pair in pairs {
            if !matched.contains(pair.u) && !matched.contains(pair.v) {
                matched.insert(pair.u)
                matched.insert(pair.v)
                if pair.distSq > 1e-6 {
                    let ptU = endpoints[pair.u]
                    let ptV = endpoints[pair.v]
                    stitched.append(
                        RoomPlanSnapshot.WallSegment(
                            startX: ptU.x,
                            startZ: ptU.y,
                            endX: ptV.x,
                            endZ: ptV.y
                        )
                    )
                }
            }
        }

        guard matched.count == endpoints.count else {
            return nil
        }
        return stitched
    }

    /// Evaluates whether a 2D floor position lies inside an arbitrary room polygon using ray-casting.
    public static func isPointInsidePolygon(
        _ point: SIMD2<Float>,
        walls: [RoomPlanSnapshot.WallSegment]
    ) -> Bool {
        let effectiveWalls = closeWallPolygon(walls) ?? walls
        var inside = false
        for wall in effectiveWalls {
            if (wall.startZ > point.y) != (wall.endZ > point.y) {
                let crossingX = wall.startX + (point.y - wall.startZ)
                    * (wall.endX - wall.startX) / (wall.endZ - wall.startZ)
                if point.x < crossingX {
                    inside.toggle()
                }
            }
        }
        return inside
    }

    /// Projects an outside candidate point to the nearest interior point inside the room polygon.
    public static func projectIntoRoomPolygon(
        _ point: SIMD2<Float>,
        walls: [RoomPlanSnapshot.WallSegment],
        margin: Float = 0.20
    ) -> SIMD2<Float> {
        let effectiveWalls = closeWallPolygon(walls) ?? walls
        if isPointInsidePolygon(point, walls: effectiveWalls) {
            return point
        }

        var bestCandidate = point
        var minDistance: Float = .greatestFiniteMagnitude

        for wall in effectiveWalls {
            let dx = wall.endX - wall.startX
            let dz = wall.endZ - wall.startZ
            let segLenSq = dx * dx + dz * dz
            guard segLenSq > 1e-5 else { continue }

            let t = max(0.0, min(1.0, ((point.x - wall.startX) * dx + (point.y - wall.startZ) * dz) / segLenSq))
            let projX = wall.startX + t * dx
            let projZ = wall.startZ + t * dz

            let lenSeg = sqrt(segLenSq)
            let nx = -dz / lenSeg
            let nz = dx / lenSeg

            for sign: Float in [-1.0, 1.0] {
                let cand = SIMD2<Float>(projX + sign * nx * margin, projZ + sign * nz * margin)
                if isPointInsidePolygon(cand, walls: effectiveWalls) {
                    let d = simd_distance(point, cand)
                    if d < minDistance {
                        minDistance = d
                        bestCandidate = cand
                    }
                }
            }
        }

        return bestCandidate
    }

    /// Clamps a furniture item's 2D floor position within room dimensions centered at (0, 0).
    public static func clampToRoomBoundaries(
        position: SIMD2<Float>,
        furnitureWidth: Float,
        furnitureLength: Float,
        rotationYaw: Float,
        roomWidth: Float,
        roomLength: Float
    ) -> SIMD2<Float> {
        clampToRoomBoundaries(
            position: position,
            furnitureWidth: furnitureWidth,
            furnitureLength: furnitureLength,
            rotationYaw: rotationYaw,
            minX: -(roomWidth * 0.5),
            maxX: roomWidth * 0.5,
            minZ: -(roomLength * 0.5),
            maxZ: roomLength * 0.5
        )
    }

    /// Advances yaw rotation by +90 degrees (pi/2 radians) snapped to orthogonal increments in [0, 2pi).
    public static func stepRotation90(currentYaw: Float) -> Float {
        let twoPi = Float.pi * 2.0
        let normalized = (currentYaw.truncatingRemainder(dividingBy: twoPi) + twoPi).truncatingRemainder(dividingBy: twoPi)
        let quarterPi = Float.pi / 2.0
        let stepIndex = Int(round(normalized / quarterPi)) + 1
        return Float(stepIndex % 4) * quarterPi
    }

    /// Normalizes raw yaw into [0, 2pi) and snaps to the nearest increment (default 90°, pi/2)
    /// if within a magnetic snap threshold.
    public static func snapYaw(
        rawYaw: Float,
        step: Float = .pi / 2.0,
        threshold: Float = 0.12
    ) -> (yaw: Float, didSnap: Bool) {
        let twoPi = Float.pi * 2.0
        let normalized = (rawYaw.truncatingRemainder(dividingBy: twoPi) + twoPi).truncatingRemainder(dividingBy: twoPi)
        let nearestIndex = round(normalized / step)
        let nearestTarget = nearestIndex * step
        let diff = abs(normalized - nearestTarget)
        if diff < threshold || abs(diff - twoPi) < threshold {
            let snapped = (nearestTarget.truncatingRemainder(dividingBy: twoPi) + twoPi).truncatingRemainder(dividingBy: twoPi)
            return (snapped, true)
        }
        return (normalized, false)
    }

    /// Checks whether two furniture pieces collide using 3D vertical clearance and 2D OBB SAT,
    /// with an architectural tuck-in allowance for chairs nesting under desks or tables.
    public static func checkCollision(
        itemA: FurnitureCollisionProxy,
        itemB: FurnitureCollisionProxy
    ) -> Bool {
        guard itemA.id != itemB.id else { return false }

        // 1. Vertical interval check (position.y is the base Y of the furniture)
        let botA = itemA.position.y
        let topA = itemA.position.y + itemA.dimensions.y
        let botB = itemB.position.y
        let topB = itemB.position.y + itemB.dimensions.y

        let verticalOverlap = min(topA, topB) - max(botA, botB)
        guard verticalOverlap > 0.05 else { return false }

        // 2. 2D Oriented Bounding Box (SAT)
        let posA = SIMD2<Float>(itemA.position.x, itemA.position.z)
        let posB = SIMD2<Float>(itemB.position.x, itemB.position.z)

        let uA = SIMD2<Float>(cos(itemA.rotationYaw), -sin(itemA.rotationYaw))
        let vA = SIMD2<Float>(sin(itemA.rotationYaw), cos(itemA.rotationYaw))
        let hA = SIMD2<Float>(itemA.dimensions.x * 0.5, itemA.dimensions.z * 0.5)

        let uB = SIMD2<Float>(cos(itemB.rotationYaw), -sin(itemB.rotationYaw))
        let vB = SIMD2<Float>(sin(itemB.rotationYaw), cos(itemB.rotationYaw))
        let hB = SIMD2<Float>(itemB.dimensions.x * 0.5, itemB.dimensions.z * 0.5)

        let testAxes = [uA, vA, uB, vB]

        let delta = posB - posA
        for axis in testAxes {
            let len = simd_length(axis)
            guard len > 1e-5 else { continue }
            let unit = axis / len

            let dist = abs(dot(delta, unit))
            let rA = hA.x * abs(dot(uA, unit)) + hA.y * abs(dot(vA, unit))
            let rB = hB.x * abs(dot(uB, unit)) + hB.y * abs(dot(vB, unit))

            let overlap = (rA + rB) - dist
            if overlap <= 0 {
                // Separating axis found: boxes do not intersect
                return false
            }
        }

        // 3. Category-Aware Tuck-In Allowance: Chair under Table / Desk
        let isNestingPair = (itemA.category.lowercased() == "chair" && (itemB.category.lowercased() == "desk" || itemB.category.lowercased() == "table"))
            || (itemB.category.lowercased() == "chair" && (itemA.category.lowercased() == "desk" || itemA.category.lowercased() == "table"))

        if isNestingPair {
            let chair = itemA.category.lowercased() == "chair" ? itemA : itemB
            let table = itemA.category.lowercased() == "chair" ? itemB : itemA

            let chairPos = SIMD2<Float>(chair.position.x, chair.position.z)
            let tablePos = SIMD2<Float>(table.position.x, table.position.z)

            // Table depth axis (local v along Z)
            let tableV = SIMD2<Float>(sin(table.rotationYaw), cos(table.rotationYaw))
            let depthOffset = abs(dot(chairPos - tablePos, tableV))

            let tableHalfDepth = table.dimensions.z * 0.5
            let chairHalfDepth = chair.dimensions.z * 0.5
            let chairDepth = chair.dimensions.z

            // Permitted tuck-in: chair seat penetrates up to 65% of chair depth into table,
            // but chair center must remain outside the table inner core (depthOffset >= tableHalfDepth * 0.40)
            let penetration = (tableHalfDepth + chairHalfDepth) - depthOffset
            let maxAllowedTuck = chairDepth * 0.65

            if penetration <= maxAllowedTuck && depthOffset >= (tableHalfDepth * 0.40) {
                // Natural tuck-in allowed!
                return false
            }
        }

        // Rigid collision confirmed
        return true
    }

    /// Evaluates whether candidate placement is valid given room dimensions and existing furniture.
    public static func canPlace(
        candidate: FurnitureCollisionProxy,
        inRoomWidth roomWidth: Float,
        inRoomLength roomLength: Float,
        obstacles: [FurnitureCollisionProxy]
    ) -> Bool {
        // Perimeter bounds
        let pos2D = SIMD2<Float>(candidate.position.x, candidate.position.z)
        let clamped = clampToRoomBoundaries(
            position: pos2D,
            furnitureWidth: candidate.dimensions.x,
            furnitureLength: candidate.dimensions.z,
            rotationYaw: candidate.rotationYaw,
            roomWidth: roomWidth,
            roomLength: roomLength
        )
        guard simd_distance(pos2D, clamped) < 0.01 else {
            return false
        }

        // Obstacles collision
        for obstacle in obstacles where obstacle.id != candidate.id {
            if checkCollision(itemA: candidate, itemB: obstacle) {
                return false
            }
        }

        return true
    }
}
