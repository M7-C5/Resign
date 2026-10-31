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

public struct SpatialClearanceEngine: Sendable {
    public init() {}

    public struct BoundingBox2D: Equatable, Sendable {
        public var minX: Float
        public var maxX: Float
        public var minZ: Float
        public var maxZ: Float

        public var width: Float { maxX - minX }
        public var length: Float { maxZ - minZ }
        public var centerX: Float { (minX + maxX) / 2 }
        public var centerZ: Float { (minZ + maxZ) / 2 }

        public func distance(to other: BoundingBox2D) -> Float {
            let dx = max(0, max(minX - other.maxX, other.minX - maxX))
            let dz = max(0, max(minZ - other.maxZ, other.minZ - maxZ))
            return sqrt(dx * dx + dz * dz)
        }

        public func intersects(_ other: BoundingBox2D) -> Bool {
            return minX < other.maxX && maxX > other.minX && minZ < other.maxZ && maxZ > other.minZ
        }
    }

    public func boundingBox(for furniture: Furniture) -> BoundingBox2D {
        let yaw = furniture.rotationYaw
        let cosY = abs(cos(yaw))
        let sinY = abs(sin(yaw))

        let extentX = (furniture.width * cosY + furniture.length * sinY) / 2.0
        let extentZ = (furniture.width * sinY + furniture.length * cosY) / 2.0

        return BoundingBox2D(
            minX: furniture.positionX - extentX,
            maxX: furniture.positionX + extentX,
            minZ: furniture.positionZ - extentZ,
            maxZ: furniture.positionZ + extentZ
        )
    }

    // MARK: - Full Room Evaluation

    public func evaluate(room: Room, layout: Layout) -> [SpatialViolation] {
        var violations: [SpatialViolation] = []
        violations.append(contentsOf: checkWalkwayClearances(furnitures: layout.furnitures, roomLength: room.length, roomWidth: room.width))
        violations.append(contentsOf: checkDeskClearance(furnitures: layout.furnitures, roomLength: room.length, roomWidth: room.width))
        violations.append(contentsOf: checkBedClearance(furnitures: layout.furnitures, roomLength: room.length, roomWidth: room.width))
        violations.append(contentsOf: checkDoorSwing(
            furnitures: layout.furnitures,
            doors: room.openings.filter { $0.type.lowercased() == "door" },
            roomWidth: room.width,
            roomLength: room.length
        ))
        return violations
    }

    // MARK: - Walkway Rules (R1: Critical < 76.2 cm, R2: Recommended < 91.4 cm)

    public func checkWalkwayClearances(furnitures: [Furniture], roomLength: Float, roomWidth: Float) -> [SpatialViolation] {
        var violations: [SpatialViolation] = []
        let active = furnitures.filter { !$0.isArchived }

        guard active.count >= 2 else { return [] }

        for i in 0..<active.count {
            for j in (i + 1)..<active.count {
                let itemA = active[i]
                let itemB = active[j]

                // Desks and chairs designed to be paired are evaluated in checkDeskClearance
                let isDeskChairPair = (itemA.category == "desk" && itemB.category == "chair") ||
                                      (itemA.category == "chair" && itemB.category == "desk")
                if isDeskChairPair { continue }

                let boxA = boundingBox(for: itemA)
                let boxB = boundingBox(for: itemB)
                let distMeters = boxA.distance(to: boxB)
                let distCm = Double(distMeters * 100.0)

                if distCm < 76.2 {
                    violations.append(
                        SpatialViolation(
                            ruleId: PaneroZelnikRule.walkwayCritical,
                            ruleTitle: "Critical Walkway Bottleneck",
                            severity: .critical,
                            measuredClearanceCm: (distCm * 10).rounded() / 10,
                            requiredClearanceCm: 76.2,
                            itemIds: [itemA.id, itemB.id],
                            message: "Walkway between \(itemA.name) and \(itemB.name) is \(Int(distCm.rounded())) cm. Panero & Zelnik R1 requires at least 76.2 cm."
                        )
                    )
                } else if distCm < 91.4 {
                    violations.append(
                        SpatialViolation(
                            ruleId: PaneroZelnikRule.walkwayRecommended,
                            ruleTitle: "Sub-optimal Walkway Clearance",
                            severity: .warning,
                            measuredClearanceCm: (distCm * 10).rounded() / 10,
                            requiredClearanceCm: 91.4,
                            itemIds: [itemA.id, itemB.id],
                            message: "Walkway between \(itemA.name) and \(itemB.name) is \(Int(distCm.rounded())) cm. Panero & Zelnik R2 recommends 91.4 cm for effortless passage."
                        )
                    )
                }
            }
        }

        return violations
    }

    // MARK: - Desk Rear Clearance (R3: Min 76.2 cm)

    public func checkDeskClearance(furnitures: [Furniture], roomLength: Float, roomWidth: Float) -> [SpatialViolation] {
        var violations: [SpatialViolation] = []
        let desks = furnitures.filter { !$0.isArchived && ($0.category == "desk" || $0.name.localizedCaseInsensitiveContains("desk")) }
        let chairs = furnitures.filter { !$0.isArchived && ($0.category == "chair" || $0.name.localizedCaseInsensitiveContains("chair")) }
        let obstacles = furnitures.filter { !$0.isArchived }

        let halfLength = roomLength / 2.0

        for desk in desks {
            let deskBox = boundingBox(for: desk)
            // Look for paired chair
            let pairedChair = chairs.min(by: {
                boundingBox(for: $0).distance(to: deskBox) < boundingBox(for: $1).distance(to: deskBox)
            })

            let referenceBox: BoundingBox2D
            var involvedIDs: [UUID] = [desk.id]
            let dx: Float
            let dz: Float
            if let chair = pairedChair, boundingBox(for: chair).distance(to: deskBox) < 1.2 {
                referenceBox = boundingBox(for: chair)
                involvedIDs.append(chair.id)
                dx = referenceBox.centerX - deskBox.centerX
                dz = referenceBox.centerZ - deskBox.centerZ
            } else {
                referenceBox = deskBox
                let front = FurnitureOrientation.frontDirection(of: desk)
                dx = front.x
                dz = front.z
            }
            let halfWidth = roomWidth / 2.0

            var rearClearance: Float
            if abs(dx) > abs(dz) {
                if dx > 0 {
                    // Pulling toward +X (East)
                    var minDist = max(0, halfWidth - referenceBox.maxX)
                    for obstacle in obstacles where !involvedIDs.contains(obstacle.id) {
                        let obsBox = boundingBox(for: obstacle)
                        if obsBox.minX >= referenceBox.maxX && obsBox.maxZ > referenceBox.minZ && obsBox.minZ < referenceBox.maxZ {
                            minDist = min(minDist, obsBox.minX - referenceBox.maxX)
                        }
                    }
                    rearClearance = minDist
                } else {
                    // Pulling toward -X (West)
                    var minDist = max(0, referenceBox.minX - (-halfWidth))
                    for obstacle in obstacles where !involvedIDs.contains(obstacle.id) {
                        let obsBox = boundingBox(for: obstacle)
                        if obsBox.maxX <= referenceBox.minX && obsBox.maxZ > referenceBox.minZ && obsBox.minZ < referenceBox.maxZ {
                            minDist = min(minDist, referenceBox.minX - obsBox.maxX)
                        }
                    }
                    rearClearance = minDist
                }
            } else if dz >= 0 {
                // Moving towards positive Z (South)
                let wallDist = halfLength - referenceBox.maxZ
                var minDist = max(0, wallDist)
                for obstacle in obstacles where !involvedIDs.contains(obstacle.id) {
                    let obsBox = boundingBox(for: obstacle)
                    if obsBox.minZ >= referenceBox.maxZ && obsBox.maxX > referenceBox.minX && obsBox.minX < referenceBox.maxX {
                        minDist = min(minDist, obsBox.minZ - referenceBox.maxZ)
                    }
                }
                rearClearance = minDist
            } else {
                // Moving towards negative Z (North)
                let wallDist = referenceBox.minZ - (-halfLength)
                var minDist = max(0, wallDist)
                for obstacle in obstacles where !involvedIDs.contains(obstacle.id) {
                    let obsBox = boundingBox(for: obstacle)
                    if obsBox.maxZ <= referenceBox.minZ && obsBox.maxX > referenceBox.minX && obsBox.minX < referenceBox.maxX {
                        minDist = min(minDist, referenceBox.minZ - obsBox.maxZ)
                    }
                }
                rearClearance = minDist
            }

            let rearClearanceCm = Double(rearClearance * 100.0)
            if rearClearanceCm < 76.2 {
                violations.append(
                    SpatialViolation(
                        ruleId: PaneroZelnikRule.deskRearClearance,
                        ruleTitle: "Desk Rear Pullback Restricted",
                        severity: .critical,
                        measuredClearanceCm: max(0, (rearClearanceCm * 10).rounded() / 10),
                        requiredClearanceCm: 76.2,
                        itemIds: involvedIDs,
                        message: "Clearance behind \(desk.name) chair zone is \(Int(max(0, rearClearanceCm).rounded())) cm. Panero & Zelnik R3 requires at least 76.2 cm for chair egress."
                    )
                )
            }
        }

        return violations
    }

    // MARK: - Bed Operational Zone (R4: 66–99 cm, R5: 116–157 cm)

    public func checkBedClearance(furnitures: [Furniture], roomLength: Float, roomWidth: Float) -> [SpatialViolation] {
        var violations: [SpatialViolation] = []
        let beds = furnitures.filter { !$0.isArchived && ($0.category == "bed" || $0.name.localizedCaseInsensitiveContains("bed")) }
        let obstacles = furnitures.filter { !$0.isArchived }

        let halfWidth = roomWidth / 2.0
        let halfLength = roomLength / 2.0

        for bed in beds {
            let bedBox = boundingBox(for: bed)

            let isZAligned = abs(cos(bed.rotationYaw)) >= abs(sin(bed.rotationYaw))

            let leftCm: Double
            let rightCm: Double

            if isZAligned {
                let leftWallDist = bedBox.minX - (-halfWidth)
                var minLeftDist = max(0, leftWallDist)
                for obs in obstacles where obs.id != bed.id {
                    let obsBox = boundingBox(for: obs)
                    if obsBox.maxX <= bedBox.minX && obsBox.maxZ > bedBox.minZ && obsBox.minZ < bedBox.maxZ {
                        minLeftDist = min(minLeftDist, bedBox.minX - obsBox.maxX)
                    }
                }

                let rightWallDist = halfWidth - bedBox.maxX
                var minRightDist = max(0, rightWallDist)
                for obs in obstacles where obs.id != bed.id {
                    let obsBox = boundingBox(for: obs)
                    if obsBox.minX >= bedBox.maxX && obsBox.maxZ > bedBox.minZ && obsBox.minZ < bedBox.maxZ {
                        minRightDist = min(minRightDist, obsBox.minX - bedBox.maxX)
                    }
                }

                leftCm = Double(minLeftDist * 100.0)
                rightCm = Double(minRightDist * 100.0)
            } else {
                let sideAWallDist = bedBox.minZ - (-halfLength)
                var minSideADist = max(0, sideAWallDist)
                for obs in obstacles where obs.id != bed.id {
                    let obsBox = boundingBox(for: obs)
                    if obsBox.maxZ <= bedBox.minZ && obsBox.maxX > bedBox.minX && obsBox.minX < bedBox.maxX {
                        minSideADist = min(minSideADist, bedBox.minZ - obsBox.maxZ)
                    }
                }

                let sideBWallDist = halfLength - bedBox.maxZ
                var minSideBDist = max(0, sideBWallDist)
                for obs in obstacles where obs.id != bed.id {
                    let obsBox = boundingBox(for: obs)
                    if obsBox.minZ >= bedBox.maxZ && obsBox.maxX > bedBox.minX && obsBox.minX < bedBox.maxX {
                        minSideBDist = min(minSideBDist, obsBox.minZ - bedBox.maxZ)
                    }
                }

                leftCm = Double(minSideADist * 100.0)
                rightCm = Double(minSideBDist * 100.0)
            }

            let accessibleSideCm = min(leftCm, rightCm)
            let maxSideCm = max(leftCm, rightCm)

            if accessibleSideCm > 5.0 && accessibleSideCm < 66.0 {
                violations.append(
                    SpatialViolation(
                        ruleId: PaneroZelnikRule.bedOperationalZone,
                        ruleTitle: "Bed-Making Access Restricted",
                        severity: .critical,
                        measuredClearanceCm: (accessibleSideCm * 10).rounded() / 10,
                        requiredClearanceCm: 66.0,
                        itemIds: [bed.id],
                        message: "Bed perimeter access is \(Int(accessibleSideCm.rounded())) cm. Panero & Zelnik R4 requires 66–99 cm for comfortable bed-making."
                    )
                )
            } else if maxSideCm < 66.0 {
                violations.append(
                    SpatialViolation(
                        ruleId: PaneroZelnikRule.bedOperationalZone,
                        ruleTitle: "Bed-Making Access Restricted",
                        severity: .critical,
                        measuredClearanceCm: (maxSideCm * 10).rounded() / 10,
                        requiredClearanceCm: 66.0,
                        itemIds: [bed.id],
                        message: "Bed perimeter access is \(Int(maxSideCm.rounded())) cm. Panero & Zelnik R4 requires 66–99 cm for comfortable bed-making."
                    )
                )
            }

            let requiresStorage = bed.name.localizedCaseInsensitiveContains("storage") || bed.category.localizedCaseInsensitiveContains("storage")
            if requiresStorage && maxSideCm < 116.0 {
                violations.append(
                    SpatialViolation(
                        ruleId: PaneroZelnikRule.bedStorageZone,
                        ruleTitle: "Under-Bed Storage Clearance Restricted",
                        severity: .warning,
                        measuredClearanceCm: (maxSideCm * 10).rounded() / 10,
                        requiredClearanceCm: 116.0,
                        itemIds: [bed.id],
                        message: "Under-bed storage drawer access is \(Int(maxSideCm.rounded())) cm. Panero & Zelnik R5 requires 116–157 cm for pulling out drawers."
                    )
                )
            }
        }

        return violations
    }

    // MARK: - Door Swing Clearance (R6: 100% Unobstructed)

    /// Floor area an opening door sweeps. Uses the nearest wall when the room size is known
    /// (correct for non-square rooms) and the legacy |z| >= |x| heuristic otherwise.
    public func doorSwingBox(for door: RoomOpening, roomWidth: Float? = nil, roomLength: Float? = nil) -> BoundingBox2D {
        let doorRadius = door.width
        let wall: RoomWall
        if let roomWidth, let roomLength {
            wall = RoomWall.nearest(toX: door.posX, z: door.posZ, halfWidth: roomWidth / 2, halfLength: roomLength / 2)
        } else if abs(door.posZ) >= abs(door.posX) {
            wall = door.posZ > 0 ? .south : .north
        } else {
            wall = door.posX > 0 ? .east : .west
        }

        switch wall {
        case .south:
            return BoundingBox2D(minX: door.posX - doorRadius / 2.0, maxX: door.posX + doorRadius / 2.0, minZ: door.posZ - doorRadius, maxZ: door.posZ)
        case .north:
            return BoundingBox2D(minX: door.posX - doorRadius / 2.0, maxX: door.posX + doorRadius / 2.0, minZ: door.posZ, maxZ: door.posZ + doorRadius)
        case .east:
            return BoundingBox2D(minX: door.posX - doorRadius, maxX: door.posX, minZ: door.posZ - doorRadius / 2.0, maxZ: door.posZ + doorRadius / 2.0)
        case .west:
            return BoundingBox2D(minX: door.posX, maxX: door.posX + doorRadius, minZ: door.posZ - doorRadius / 2.0, maxZ: door.posZ + doorRadius / 2.0)
        }
    }

    public func checkDoorSwing(
        furnitures: [Furniture],
        doors: [RoomOpening],
        roomWidth: Float? = nil,
        roomLength: Float? = nil
    ) -> [SpatialViolation] {
        var violations: [SpatialViolation] = []
        let active = furnitures.filter { !$0.isArchived }
        let actualDoors = doors.filter { $0.type.localizedCaseInsensitiveContains("door") }

        for door in actualDoors {
            let doorRadius = door.width
            let swingBox = doorSwingBox(for: door, roomWidth: roomWidth, roomLength: roomLength)

            for item in active {
                let itemBox = boundingBox(for: item)
                if itemBox.intersects(swingBox) {
                    violations.append(
                        SpatialViolation(
                            ruleId: PaneroZelnikRule.doorSwingUnobstructed,
                            ruleTitle: "Door Swing Obstructed",
                            severity: .critical,
                            measuredClearanceCm: 0.0,
                            requiredClearanceCm: Double(doorRadius * 100.0),
                            itemIds: [item.id],
                            message: "Door swing path is obstructed by \(item.name). Panero & Zelnik R6 requires entry doors to remain 100% unobstructed."
                        )
                    )
                }
            }
        }

        return violations
    }

    // MARK: - 3D Studio Physics, Boundaries & Rigid Collision

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
