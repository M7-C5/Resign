//
//  SpatialClearanceEngine.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation

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

            // Determine orientation: if yaw is closer to 0 or pi (cos >= sin), bed length runs along Z and sides are along X (-X, +X).
            // If yaw is closer to +/- pi/2 (sin > cos), bed length runs along X and sides are along Z (-Z, +Z).
            let isZAligned = abs(cos(bed.rotationYaw)) >= abs(sin(bed.rotationYaw))

            let leftCm: Double
            let rightCm: Double

            if isZAligned {
                // Side clearance: left side (-X) and right side (+X)
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
                // Side clearance: side A (-Z) and side B (+Z)
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

            // A bed placed directly in a corner is acceptable on one side, but the open accessible side MUST have >= 66 cm
            let accessibleSideCm = min(leftCm, rightCm)
            let maxSideCm = max(leftCm, rightCm)

            // If even the most open accessible side is < 66 cm, or if left side is restricted between 10cm and 65cm:
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

            // Check under-bed storage rule R5 if bed is marked for storage
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

        // The swing always extends from the wall toward the room centre.
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
}
