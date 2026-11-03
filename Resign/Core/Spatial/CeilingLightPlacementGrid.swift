import Foundation

/// Candidate positions in normalized plan space; saved fixtures are independent of this lattice.
struct CeilingLightPlacementGrid: Sendable {
    /// Captured aperture evidence in the same local frame as the wall segments.
    struct Opening: Sendable {
        let center: SIMD2<Float>
        let width: Float
    }

    let columns: Int
    let rows: Int
    let points: [SIMD2<Float>]
    private let bounds: RoomPlanBounds
    private let boundary: [RoomPlanSnapshot.WallSegment]?
    private let capturedWalls: [RoomPlanSnapshot.WallSegment]
    private let clearance: Float

    var hasUsableBoundary: Bool { boundary != nil }

    init(bounds: RoomPlanBounds, walls: [RoomPlanSnapshot.WallSegment],
         openings: [Opening] = [],
         maxColumns: Int = 15, maxRows: Int = 15, wallClearance: Float = 0.15) {
        self.bounds = bounds
        capturedWalls = walls.filter {
            Self.distanceSquared([$0.startX, $0.startZ], [$0.endX, $0.endZ]) > 0.0001
        }
        clearance = max(0, wallClearance)
        boundary = walls.isEmpty ? [] : Self.joinedBoundary(walls, openings: openings)
        let columnLimit = max(1, maxColumns)
        let rowLimit = max(1, maxRows)
        let spacing = max(0.65, max(bounds.width / Float(columnLimit), bounds.length / Float(rowLimit)))
        columns = Self.centeredCount(bounds.width / spacing, limit: columnLimit)
        rows = Self.centeredCount(bounds.length / spacing, limit: rowLimit)
        var candidates: [SIMD2<Float>] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let unit = SIMD2<Float>((Float(column) + 0.5) / Float(columns),
                                        (Float(row) + 0.5) / Float(rows))
                if Self.allows(unit, bounds: bounds, boundary: boundary, capturedWalls: capturedWalls, clearance: clearance) {
                    candidates.append(unit)
                }
            }
        }
        // Even display limits can still omit the center from the regular lattice.
        // Offer it explicitly only when it belongs to the usable room interior.
        let center = SIMD2<Float>(0.5, 0.5)
        if Self.allows(center, bounds: bounds, boundary: boundary, capturedWalls: capturedWalls, clearance: clearance),
           !candidates.contains(center) {
            candidates.append(center)
        }
        points = candidates
    }

    private static func centeredCount(_ desired: Float, limit: Int) -> Int {
        let count = min(limit, max(1, Int(desired.rounded())))
        // Odd row/column counts put a point on both center axes when space permits.
        return count.isMultiple(of: 2) && count < limit ? count + 1 : count
    }

    func allowsPlacement(at unit: SIMD2<Float>) -> Bool {
        Self.allows(unit, bounds: bounds, boundary: boundary, capturedWalls: capturedWalls, clearance: clearance)
    }

    private static func allows(_ unit: SIMD2<Float>, bounds: RoomPlanBounds,
                               boundary: [RoomPlanSnapshot.WallSegment]?,
                               capturedWalls: [RoomPlanSnapshot.WallSegment], clearance: Float) -> Bool {
        guard unit.x.isFinite, unit.y.isFinite,
              (0...1).contains(unit.x), (0...1).contains(unit.y), let boundary else { return false }
        let point = SIMD2<Float>(bounds.minX + unit.x * bounds.width, bounds.minZ + unit.y * bounds.length)
        if boundary.isEmpty {
            // The displayed plan is rectangular only when no captured wall metadata exists.
            return min(unit.x, 1 - unit.x) * bounds.width >= clearance
                && min(unit.y, 1 - unit.y) * bounds.length >= clearance
        }
        guard contains(point, walls: boundary) else { return false }
        return boundary.allSatisfy { distanceToWallSquared(point, $0) >= clearance * clearance }
            && capturedWalls.allSatisfy { distanceToWallSquared(point, $0) >= clearance * clearance }
    }

    /// Normalize capture fragments before joining corners. Missing walls are never replaced
    /// with a bounding rectangle, preserving concave interiors and unknown scan areas.
    private static func joinedBoundary(_ capturedWalls: [RoomPlanSnapshot.WallSegment],
                                       openings: [Opening]) -> [RoomPlanSnapshot.WallSegment]? {
        guard capturedWalls.allSatisfy({
            [$0.startX, $0.startZ, $0.endX, $0.endZ].allSatisfy(\.isFinite)
        }) else { return nil }
        let usable = capturedWalls.filter {
            distanceSquared([$0.startX, $0.startZ], [$0.endX, $0.endZ]) > 0.0001
        }
        let walls = removingOpenBranches(from: mergedWallFragments(usable + apertureBridges(walls: usable, openings: openings)))
        guard walls.count >= 3 else { return nil }
        let endpoints = walls.flatMap { [SIMD2<Float>($0.startX, $0.startZ), SIMD2<Float>($0.endX, $0.endZ)] }
        var partners: [Int] = []
        var snapped: [SIMD2<Float>] = []
        for index in endpoints.indices {
            var candidates: [(index: Int, point: SIMD2<Float>, score: Float)] = []
            for other in endpoints.indices where other / 2 != index / 2 {
                if let point = cornerMeeting(index, other, endpoints: endpoints) {
                    candidates.append((other, point, max(distanceSquared(point, endpoints[index]),
                                                         distanceSquared(point, endpoints[other]))))
                }
            }
            candidates.sort { $0.score < $1.score }
            guard let best = candidates.first else { return nil }
            // Nearby short alcove edges are not ambiguous when the actual shared corner
            // is a closer match. Equal alternatives still cannot define a safe interior.
            if candidates.count > 1, abs(candidates[1].score - best.score) < 0.000001 { return nil }
            partners.append(best.index)
            snapped.append(best.point)
        }
        guard partners.indices.allSatisfy({ partners[partners[$0]] == $0 }) else { return nil }

        // A perimeter must be one cycle, rather than multiple disconnected closed traces.
        var visited: Set<Int> = []
        var current = 0
        repeat {
            guard visited.insert(current / 2).inserted else { return nil }
            current = partners[current ^ 1]
        } while current != 0
        guard visited.count == walls.count else { return nil }

        let joined = walls.indices.map { index in
            RoomPlanSnapshot.WallSegment(startX: snapped[index * 2].x, startZ: snapped[index * 2].y,
                                         endX: snapped[index * 2 + 1].x, endZ: snapped[index * 2 + 1].y)
        }
        for index in joined.indices {
            let a = snapped[index * 2]
            let b = snapped[index * 2 + 1]
            guard distanceSquared(a, b) > 0.0001 else { return nil }
            for other in joined.indices where other > index {
                let c = snapped[other * 2]
                let d = snapped[other * 2 + 1]
                if cross(b - a, c - a) * cross(b - a, d - a) < -0.000001,
                   cross(d - c, a - c) * cross(d - c, b - c) < -0.000001 { return nil }
            }
        }
        // A closed interior island must not replace an incomplete outer room trace.
        // Pruned branches must belong inside (or along) the recovered perimeter.
        guard usable.allSatisfy({ wall in
            let midpoint = SIMD2<Float>((wall.startX + wall.endX) / 2, (wall.startZ + wall.endZ) / 2)
            return contains(midpoint, walls: joined)
                || joined.contains { distanceToWallSquared(midpoint, $0) <= 0.25 * 0.25 }
        }) else { return nil }
        return joined
    }

    /// CapturedRoom includes interior partitions as well as the perimeter. Peel off
    /// branches with a free end until only potential cycles remain. Do not choose a
    /// largest polygon: multiple surviving cycles are still rejected as ambiguous.
    private static func removingOpenBranches(from input: [RoomPlanSnapshot.WallSegment]) -> [RoomPlanSnapshot.WallSegment] {
        var walls = input
        while !walls.isEmpty {
            let endpoints = walls.flatMap { [SIMD2<Float>($0.startX, $0.startZ), SIMD2<Float>($0.endX, $0.endZ)] }
            let retained = walls.indices.filter { wall in
                (wall * 2...wall * 2 + 1).allSatisfy { index in
                    endpoints.indices.contains { other in
                        other / 2 != wall && cornerMeeting(index, other, endpoints: endpoints) != nil
                    }
                }
            }
            guard retained.count != walls.count else { break }
            walls = retained.map { walls[$0] }
        }
        return walls
    }

    /// A door/window can interrupt a captured wall without opening the ceiling footprint.
    /// Bridge only facing collinear ends whose gap matches a saved aperture's position
    /// and width. An arbitrary missing wall or concave recess has no such evidence.
    private static func apertureBridges(walls: [RoomPlanSnapshot.WallSegment],
                                        openings: [Opening]) -> [RoomPlanSnapshot.WallSegment] {
        guard !openings.isEmpty else { return [] }
        let endpoints = walls.flatMap { [SIMD2<Float>($0.startX, $0.startZ), SIMD2<Float>($0.endX, $0.endZ)] }
        var bridges: [RoomPlanSnapshot.WallSegment] = []
        for index in endpoints.indices {
            let a = endpoints[index]
            let inwardA = endpoints[index ^ 1] - a
            let axis = inwardA / sqrt(distanceSquared(inwardA, .zero))
            for other in endpoints.indices where other > index && other / 2 != index / 2 {
                let b = endpoints[other]
                let gap = b - a
                let inwardB = endpoints[other ^ 1] - b
                guard gap.x * inwardA.x + gap.y * inwardA.y < 0,
                      gap.x * inwardB.x + gap.y * inwardB.y > 0,
                      abs(cross(axis, gap)) <= 0.01,
                      abs(cross(axis, inwardB)) <= 0.01 else { continue }
                let span = sqrt(distanceSquared(a, b))
                let midpoint = (a + b) / 2
                guard openings.contains(where: {
                    $0.center.x.isFinite && $0.center.y.isFinite && $0.width.isFinite
                        && $0.width > 0 && abs($0.width - span) <= 0.3
                        && distanceSquared($0.center, midpoint) <= 0.15 * 0.15
                }) else { continue }
                bridges.append(.init(startX: a.x, startZ: a.y, endX: b.x, endZ: b.y))
            }
        }
        return bridges
    }

    private static func cornerMeeting(_ index: Int, _ other: Int,
                                      endpoints: [SIMD2<Float>]) -> SIMD2<Float>? {
        let a = endpoints[index], b = endpoints[other]
        let u = endpoints[index ^ 1] - a, v = endpoints[other ^ 1] - b
        let denominator = cross(u, v)
        // Intersect supporting lines only at nearby ends of both captured segments.
        // This repairs corner under/overshoot without closing an absent room side.
        if abs(denominator) > 0.2 * sqrt(distanceSquared(u, .zero) * distanceSquared(v, .zero)) {
            let point = a + u * (cross(b - a, v) / denominator)
            let limitA = min(0.5, sqrt(distanceSquared(u, .zero)) * 0.25)
            let limitB = min(0.5, sqrt(distanceSquared(v, .zero)) * 0.25)
            if distanceSquared(point, a) <= limitA * limitA,
               distanceSquared(point, b) <= limitB * limitB {
                return point
            }
        }
        if distanceSquared(a, b) <= 0.25 * 0.25 { return (a + b) / 2 }
        return nil
    }

    /// RoomPlan can report duplicate or overlapping pieces of the same wall face.
    /// Merge only near-collinear, touching spans; do not fill door-sized gaps.
    private static func mergedWallFragments(_ input: [RoomPlanSnapshot.WallSegment]) -> [RoomPlanSnapshot.WallSegment] {
        var walls = input
        var didMerge = true
        while didMerge {
            didMerge = false
            outer: for index in walls.indices {
                let a = SIMD2<Float>(walls[index].startX, walls[index].startZ)
                let delta = SIMD2<Float>(walls[index].endX, walls[index].endZ) - a
                let length = sqrt(distanceSquared(delta, .zero))
                guard length > 0.01 else { continue }
                let axis = delta / length
                for other in walls.indices where other > index {
                    let c = SIMD2<Float>(walls[other].startX, walls[other].startZ)
                    let d = SIMD2<Float>(walls[other].endX, walls[other].endZ)
                    guard abs(cross(axis, c - a)) <= 0.01,
                          abs(cross(axis, d - a)) <= 0.01 else { continue }
                    let tc = (c.x - a.x) * axis.x + (c.y - a.y) * axis.y
                    let td = (d.x - a.x) * axis.x + (d.y - a.y) * axis.y
                    // Do not merge across a gap: it may be a narrow concave recess
                    // with two short return walls, rather than one fragmented face.
                    guard max(tc, td) >= -0.001, min(tc, td) <= length + 0.001 else { continue }
                    let start = a + axis * min(0, min(tc, td))
                    let end = a + axis * max(length, max(tc, td))
                    walls[index] = .init(startX: start.x, startZ: start.y, endX: end.x, endZ: end.y)
                    walls.remove(at: other)
                    didMerge = true
                    break outer
                }
            }
        }
        return walls
    }

    private static func contains(_ point: SIMD2<Float>, walls: [RoomPlanSnapshot.WallSegment]) -> Bool {
        var inside = false
        for wall in walls {
            if (wall.startZ > point.y) != (wall.endZ > point.y) {
                let crossingX = wall.startX + (point.y - wall.startZ)
                    * (wall.endX - wall.startX) / (wall.endZ - wall.startZ)
                if point.x < crossingX { inside.toggle() }
            }
        }
        return inside
    }

    private static func distanceToWallSquared(_ point: SIMD2<Float>, _ wall: RoomPlanSnapshot.WallSegment) -> Float {
        let start = SIMD2<Float>(wall.startX, wall.startZ)
        let delta = SIMD2<Float>(wall.endX - wall.startX, wall.endZ - wall.startZ)
        let offset = point - start
        let t = min(1, max(0, (offset.x * delta.x + offset.y * delta.y) / max(0.0001, distanceSquared(delta, .zero))))
        return distanceSquared(point, start + delta * t)
    }

    private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

    private static func distanceSquared(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let delta = a - b
        return delta.x * delta.x + delta.y * delta.y
    }
}
