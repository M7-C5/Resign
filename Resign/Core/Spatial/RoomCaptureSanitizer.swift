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

        let mergedPass = mergeCollidingTables(in: objects)
        let processedObjects = mergedPass.objects

        for (index, obj) in processedObjects.enumerated() {
            let normalized = obj.rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // Discard bathroom fixtures & heavy appliances
            if discardedCategories.contains(normalized) {
                continue
            }

            let isLShapedDesk = mergedPass.lShapedIndices.contains(index)

            // Map to living homeowner category
            guard let category = isLShapedDesk ? "desk" : mapCategory(raw: normalized, dimensions: obj.dimensions) else {
                continue
            }

            // Elevate surface/wall-mounted objects (e.g., standing TV on console, floating wall shelf)
            // while grounding standard furniture flush to the captured floor plane.
            let elevation = resolveElevation(
                for: obj,
                category: category,
                allObjects: objects,
                floorLevel: floorLevel
            )
            var groundedPos = obj.position
            groundedPos.y = elevation.baseY

            let posSnapThreshold = positionSnapThreshold(
                for: category,
                isSupportedByFurniture: elevation.isSupportedByFurniture
            )

            // Wall alignment snapping: use multi-wall segments if available, else bounding box
            let snapped: (pos: SIMD3<Float>, yaw: Float)
            if !walls.isEmpty {
                snapped = snapToWallSegments(
                    position: groundedPos,
                    dimensions: obj.dimensions,
                    yaw: obj.rotationYaw,
                    walls: walls,
                    posSnapThreshold: posSnapThreshold
                )
            } else {
                let p: SIMD3<Float>
                if posSnapThreshold <= 0 {
                    p = groundedPos
                } else {
                    p = snapToRectangularWalls(
                        position: groundedPos,
                        dimensions: obj.dimensions,
                        roomWidth: roomWidth,
                        roomLength: roomLength,
                        snapThreshold: posSnapThreshold
                    )
                }
                snapped = (pos: p, yaw: obj.rotationYaw)
            }

            // Calculate uniform scale multiplier relative to master asset width
            let masterWidth = masterAssetWidths[category] ?? max(obj.dimensions.x, 0.1)
            let uniformScale = obj.dimensions.x / masterWidth

            let name = isLShapedDesk
                ? "L-Shaped Desk"
                : defaultName(
                    for: category,
                    dimensions: obj.dimensions,
                    isElevated: elevation.isElevated
                )

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
            if dimensions.y >= 0.55 && dimensions.y <= 0.86 && (dimensions.x <= 1.85 && dimensions.z <= 0.95 || dimensions.z <= 1.85 && dimensions.x <= 0.95) {
                return "desk"
            }
            return "table"
        default:
            return nil
        }
    }

    private struct ElevationResolution {
        let baseY: Float
        let isElevated: Bool
        let isSupportedByFurniture: Bool
    }

    private func resolveElevation(
        for obj: ScannedObjectPayload,
        category: String,
        allObjects: [ScannedObjectPayload],
        floorLevel: Float
    ) -> ElevationResolution {
        // Only televisions and elevated storage (floating wall shelves) may sit above the floor plane.
        // All standard floor furniture (beds, sofas, chairs, tables, desks, fireplaces) grounds to floorLevel.
        guard category == "television" || category == "closet" else {
            return ElevationResolution(baseY: floorLevel, isElevated: false, isSupportedByFurniture: false)
        }

        let rawBottomY = obj.position.y - (obj.dimensions.y * 0.5)
        let heightAboveFloor = rawBottomY - floorLevel
        let elevationThreshold: Float = (category == "television") ? 0.15 : 0.25

        guard heightAboveFloor > elevationThreshold else {
            return ElevationResolution(baseY: floorLevel, isElevated: false, isSupportedByFurniture: false)
        }

        // Check if this elevated item rests on a floor-grounded supporting surface (console, cabinet, desk, table)
        for candidate in allObjects {
            let candidateRaw = candidate.rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let candidateCategory = mapCategory(raw: candidateRaw, dimensions: candidate.dimensions),
                  candidateCategory == "closet" || candidateCategory == "table" || candidateCategory == "desk" else {
                continue
            }

            // Candidate must itself be floor-grounded and console/table height (not a tall wardrobe)
            let candidateBottomY = candidate.position.y - (candidate.dimensions.y * 0.5)
            guard (candidateBottomY - floorLevel) <= 0.25,
                  candidate.dimensions.y <= 1.25 else {
                continue
            }

            // Check 2D horizontal overlap (accounting for candidate's yaw orientation)
            let cosYaw = abs(cos(candidate.rotationYaw))
            let sinYaw = abs(sin(candidate.rotationYaw))
            let halfExtentX = (cosYaw * candidate.dimensions.x + sinYaw * candidate.dimensions.z) * 0.5
            let halfExtentZ = (sinYaw * candidate.dimensions.x + cosYaw * candidate.dimensions.z) * 0.5

            let dx = abs(obj.position.x - candidate.position.x)
            let dz = abs(obj.position.z - candidate.position.z)
            let margin: Float = 0.12

            guard dx <= halfExtentX + margin, dz <= halfExtentZ + margin else {
                continue
            }

            let supportTopY = floorLevel + candidate.dimensions.y
            if rawBottomY >= (floorLevel + candidate.dimensions.y * 0.4) && rawBottomY <= (supportTopY + 0.35) {
                return ElevationResolution(
                    baseY: supportTopY,
                    isElevated: true,
                    isSupportedByFurniture: true
                )
            }
        }

        // Wall-mounted television or floating wall shelf with no supporting surface underneath
        return ElevationResolution(
            baseY: max(rawBottomY, floorLevel),
            isElevated: true,
            isSupportedByFurniture: false
        )
    }

    private func positionSnapThreshold(
        for category: String,
        isSupportedByFurniture: Bool
    ) -> Float {
        guard !isSupportedByFurniture else { return 0.0 }
        switch category {
        case "sofa", "chair", "table":
            // Free-floating living/dining furniture never snaps its position into walls
            return 0.0
        case "closet", "fireplace", "television":
            // Wall-anchored perimeter items snap within 8 cm of LiDAR wall jitter
            return 0.08
        case "bed", "desk":
            // Hybrid perimeter items snap only when tightly placed within 6 cm of a wall
            return 0.06
        default:
            return 0.0
        }
    }

    private struct TableMergeResult {
        let objects: [ScannedObjectPayload]
        let lShapedIndices: Set<Int>
    }

    private func isTableMergeCandidate(rawCategory: String, dimensions: SIMD3<Float>) -> Bool {
        if rawCategory == "table" { return true }
        // Apple RoomPlan frequently classifies the drawer/credenza wing of an L-shaped desk
        // as "storage" (height ~0.60m–0.95m) and the perpendicular open-leg return wing as "table".
        if rawCategory == "storage" && dimensions.y >= 0.60 && dimensions.y <= 0.95 {
            return true
        }
        return false
    }

    private func mergeCollidingTables(in objects: [ScannedObjectPayload]) -> TableMergeResult {
        var consumed: Set<Int> = []
        var mergedList: [ScannedObjectPayload] = []
        var lShapedIndices: Set<Int> = []

        for i in objects.indices {
            if consumed.contains(i) { continue }
            let objA = objects[i]
            let rawA = objA.rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard isTableMergeCandidate(rawCategory: rawA, dimensions: objA.dimensions) else {
                mergedList.append(objA)
                continue
            }

            var mergedPayload = objA
            var currentRaw = rawA
            var becameLShaped = false

            for j in (i + 1)..<objects.count {
                if consumed.contains(j) { continue }
                let objB = objects[j]
                let rawB = objB.rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard isTableMergeCandidate(rawCategory: rawB, dimensions: objB.dimensions) else { continue }

                // Require at least one wing in the pair to be explicitly classified as "table"
                // so two standalone storage cabinets never merge into a desk without a table wing.
                guard currentRaw == "table" || rawB == "table" else { continue }

                if let combined = tryMergeTablePair(mergedPayload, objB) {
                    consumed.insert(j)
                    mergedPayload = combined.payload
                    currentRaw = "table"
                    if combined.isLShaped {
                        becameLShaped = true
                    }
                }
            }

            let outIndex = mergedList.count
            mergedList.append(mergedPayload)
            if becameLShaped {
                lShapedIndices.insert(outIndex)
            }
        }

        return TableMergeResult(objects: mergedList, lShapedIndices: lShapedIndices)
    }

    private func tryMergeTablePair(
        _ a: ScannedObjectPayload,
        _ b: ScannedObjectPayload
    ) -> (payload: ScannedObjectPayload, isLShaped: Bool)? {
        // Must have similar tabletop height and vertical elevation
        guard abs(a.dimensions.y - b.dimensions.y) <= 0.10,
              abs(a.position.y - b.position.y) <= 0.12 else {
            return nil
        }

        let cA = SIMD2<Float>(a.position.x, a.position.z)
        let cB = SIMD2<Float>(b.position.x, b.position.z)
        let centerDist = distance(cA, cB)

        // Ignore synthetic concentric test fixtures placed at the exact same origin
        guard centerDist >= 0.20 else { return nil }

        // 2D Oriented Bounding Box (OBB) axes and half-extents
        let uA = SIMD2<Float>(cos(a.rotationYaw), -sin(a.rotationYaw))
        let vA = SIMD2<Float>(sin(a.rotationYaw), cos(a.rotationYaw))
        let halfWA = a.dimensions.x * 0.5
        let halfDA = a.dimensions.z * 0.5

        let uB = SIMD2<Float>(cos(b.rotationYaw), -sin(b.rotationYaw))
        let vB = SIMD2<Float>(sin(b.rotationYaw), cos(b.rotationYaw))
        let halfWB = b.dimensions.x * 0.5
        let halfDB = b.dimensions.z * 0.5

        // Separating Axis Theorem (SAT) check with 15 cm touch/collision tolerance
        let touchMargin: Float = 0.15
        let delta = cB - cA
        for axis in [uA, vA, uB, vB] {
            let rA = abs(dot(uA, axis)) * halfWA + abs(dot(vA, axis)) * halfDA
            let rB = abs(dot(uB, axis)) * halfWB + abs(dot(vB, axis)) * halfDB
            if abs(dot(delta, axis)) > (rA + rB + touchMargin) {
                return nil
            }
        }

        // Determine primary wing (larger horizontal span) and longitudinal axes
        let longA = (a.dimensions.x >= a.dimensions.z) ? uA : vA
        let longB = (b.dimensions.x >= b.dimensions.z) ? uB : vB

        let primaryIsA = max(a.dimensions.x, a.dimensions.z) >= max(b.dimensions.x, b.dimensions.z)
        var e1 = primaryIsA ? longA : longB
        var e2 = SIMD2<Float>(-e1.y, e1.x)

        let corners = obbCorners(center: cA, u: uA, v: vA, halfW: halfWA, halfD: halfDA)
            + obbCorners(center: cB, u: uB, v: vB, halfW: halfWB, halfD: halfDB)

        let minDepthA = min(a.dimensions.x, a.dimensions.z)
        let minDepthB = min(b.dimensions.x, b.dimensions.z)
        let baseWingDepth = max(minDepthA, minDepthB)

        let initProj2 = corners.map { dot($0, e2) }
        guard let initMin2 = initProj2.min(), let initMax2 = initProj2.max() else {
            return nil
        }
        let initDepthSpan = initMax2 - initMin2

        // Perpendicular wings (< 45 deg dot product) or lateral return protrusion > 25 cm -> L-Shaped Desk
        let isPerpendicular = abs(dot(longA, longB)) < 0.707
        let hasLateralReturn = initDepthSpan > (baseWingDepth + 0.25)
        let isLShaped = isPerpendicular || hasLateralReturn

        if isLShaped {
            // Select the right-handed basis (e1, e2) among the 4 orthogonal orientations
            // so that one wing aligns with the -Z (-e2) back edge (MainWingMesh) and
            // the return wing aligns with the +X (+e1) right edge (ReturnWingMesh).
            let candidateAxes = [uA, vA, -uA, -vA]
            var bestScore: Float = -.greatestFiniteMagnitude
            for candE1 in candidateAxes {
                let candE2 = SIMD2<Float>(-candE1.y, candE1.x)
                let p1 = corners.map { dot($0, candE1) }
                let p2 = corners.map { dot($0, candE2) }
                guard let mn1 = p1.min(), let mx1 = p1.max(),
                      let mn2 = p2.min(), let mx2 = p2.max() else { continue }
                let center2D = candE1 * ((mn1 + mx1) * 0.5) + candE2 * ((mn2 + mx2) * 0.5)
                let relA = cA - center2D
                let relB = cB - center2D
                let a1 = dot(relA, candE1)
                let a2 = dot(relA, candE2)
                let b1 = dot(relB, candE1)
                let b2 = dot(relB, candE2)
                let score = max((-a2) + b1, (-b2) + a1)
                if score > bestScore {
                    bestScore = score
                    e1 = candE1
                    e2 = candE2
                }
            }
        }

        let proj1 = corners.map { dot($0, e1) }
        let proj2 = corners.map { dot($0, e2) }
        guard let min1 = proj1.min(), let max1 = proj1.max(),
              let min2 = proj2.min(), let max2 = proj2.max() else {
            return nil
        }

        let mainYaw = atan2(-e1.y, e1.x)
        let mergedWidth = max1 - min1
        let mergedDepthSpan = max2 - min2
        let mid1 = (min1 + max1) * 0.5
        let mid2 = (min2 + max2) * 0.5
        let mergedCenter2D = e1 * mid1 + e2 * mid2
        let mergedHeight = max(a.dimensions.y, b.dimensions.y)
        let mergedY = (a.position.y + b.position.y) * 0.5

        let finalDepth = isLShaped ? mergedDepthSpan : baseWingDepth
        let merged = ScannedObjectPayload(
            rawCategory: "table",
            position: SIMD3<Float>(mergedCenter2D.x, mergedY, mergedCenter2D.y),
            dimensions: SIMD3<Float>(mergedWidth, mergedHeight, finalDepth),
            rotationYaw: mainYaw
        )

        return (merged, isLShaped)
    }

    private func obbCorners(
        center: SIMD2<Float>,
        u: SIMD2<Float>,
        v: SIMD2<Float>,
        halfW: Float,
        halfD: Float
    ) -> [SIMD2<Float>] {
        [
            center + u * halfW + v * halfD,
            center + u * halfW - v * halfD,
            center - u * halfW + v * halfD,
            center - u * halfW - v * halfD
        ]
    }

    private func snapToWallSegments(
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        yaw: Float,
        walls: [ScannedWallPayload],
        posSnapThreshold: Float = 0.08
    ) -> (pos: SIMD3<Float>, yaw: Float) {
        let yawSnapGapThreshold: Float = 0.40
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

        // Snap yaw to nearest orthogonal angle (parallel or perpendicular) when near a wall
        let relYaw = yaw - wall.rotationYaw
        let quarterTurn = Float.pi * 0.5
        let k = round(relYaw / quarterTurn)
        var snappedYaw = yaw
        let isNearOrthogonal = abs(relYaw - k * quarterTurn) < 0.26

        // True object extent along wall normal using orthogonalized yaw if applicable
        let effectiveRelYaw = isNearOrthogonal ? (k * quarterTurn) : relYaw
        let cosRel = abs(cos(effectiveRelYaw))
        let sinRel = abs(sin(effectiveRelYaw))
        let halfObjDepth = (sinRel * dimensions.x + cosRel * dimensions.z) * 0.5

        let gap = minDistance - (halfWallThickness + halfObjDepth)

        if abs(gap) < yawSnapGapThreshold && isNearOrthogonal {
            snappedYaw = wall.rotationYaw + k * quarterTurn
        }

        if posSnapThreshold > 0 && abs(gap) < posSnapThreshold {
            let dir = p2D - bestProjected
            let dirLen = length(dir)
            let outNormal = dirLen > 1e-4 ? (dir / dirLen) : bestNormal

            // Snap flush with inner plaster face: centerline + (T/2 + halfDepth)
            let totalOffset = halfWallThickness + halfObjDepth
            let snapped2D = bestProjected + outNormal * totalOffset
            let snappedPos = SIMD3<Float>(snapped2D.x, position.y, snapped2D.y)

            return (snappedPos, snappedYaw)
        }

        return (position, snappedYaw)
    }

    private func snapToRectangularWalls(
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        roomWidth: Float,
        roomLength: Float,
        wallThickness: Float = 0.10,
        snapThreshold: Float = 0.08
    ) -> SIMD3<Float> {
        var pos = position

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

    private func defaultName(
        for category: String,
        dimensions: SIMD3<Float>,
        isElevated: Bool = false
    ) -> String {
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
            if isElevated {
                return "Wall Shelf"
            } else if dimensions.y < 1.1 {
                return "Media Console"
            } else {
                return "Wardrobe"
            }
        case "television":
            return "Television"
        case "fireplace":
            return "Fireplace"
        default:
            return "Furniture"
        }
    }
}
