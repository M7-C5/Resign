import Foundation

/// Candidate positions in normalized plan space; saved fixtures are independent of this lattice.
struct CeilingLightPlacementGrid: Sendable {
    let columns: Int
    let rows: Int
    let points: [SIMD2<Float>]
    private let bounds: RoomPlanBounds
    private let boundary: [RoomPlanSnapshot.WallSegment]?
    private let clearance: Float

    var hasUsableBoundary: Bool { boundary != nil }

    init(bounds: RoomPlanBounds, walls: [RoomPlanSnapshot.WallSegment],
         maxColumns: Int = 15, maxRows: Int = 15, wallClearance: Float = 0.15) {
        self.bounds = bounds
        clearance = max(0, wallClearance)
        boundary = walls.isEmpty ? [] : Self.joinedBoundary(walls)
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
                if Self.allows(unit, bounds: bounds, boundary: boundary, clearance: clearance) {
                    candidates.append(unit)
                }
            }
        }
        // Even display limits can still omit the center from the regular lattice.
        // Offer it explicitly only when it belongs to the usable room interior.
        let center = SIMD2<Float>(0.5, 0.5)
        if Self.allows(center, bounds: bounds, boundary: boundary, clearance: clearance),
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
        Self.allows(unit, bounds: bounds, boundary: boundary, clearance: clearance)
    }

    private static func allows(_ unit: SIMD2<Float>, bounds: RoomPlanBounds,
                               boundary: [RoomPlanSnapshot.WallSegment]?, clearance: Float) -> Bool {
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
    }

    /// Snap uniquely matching endpoints across small scan gaps. Never invent a rectangular
    /// interior when captured wall traces are incomplete, ambiguous, or self-intersecting.
    private static func joinedBoundary(_ walls: [RoomPlanSnapshot.WallSegment]) -> [RoomPlanSnapshot.WallSegment]? {
        guard walls.count >= 3 else { return nil }
        let endpoints = walls.flatMap { [SIMD2<Float>($0.startX, $0.startZ), SIMD2<Float>($0.endX, $0.endZ)] }
        guard endpoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var snapped: [SIMD2<Float>] = []
        for index in endpoints.indices {
            let matches = endpoints.indices.filter { other in
                other / 2 != index / 2 && distanceSquared(endpoints[index], endpoints[other]) <= 0.25 * 0.25
            }
            guard matches.count == 1, let match = matches.first else { return nil }
            snapped.append((endpoints[index] + endpoints[match]) / 2)
        }
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
        return joined
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
