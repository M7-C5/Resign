import Foundation

/// Candidate positions in normalized plan space; saved fixtures are independent of this lattice.
struct CeilingLightPlacementGrid: Sendable {
    let columns: Int
    let rows: Int
    let points: [SIMD2<Float>]

    init(bounds: RoomPlanBounds, walls: [RoomPlanSnapshot.WallSegment],
         maxColumns: Int = 12, maxRows: Int = 12) {
        let columnLimit = max(1, maxColumns)
        let rowLimit = max(1, maxRows)
        let spacing = max(0.85, max(bounds.width / Float(columnLimit), bounds.length / Float(rowLimit)))
        columns = min(columnLimit, max(1, Int((bounds.width / spacing).rounded())))
        rows = min(rowLimit, max(1, Int((bounds.length / spacing).rounded())))
        let closed = Self.isClosed(walls)
        var candidates: [SIMD2<Float>] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let unit = SIMD2<Float>((Float(column) + 0.5) / Float(columns),
                                        (Float(row) + 0.5) / Float(rows))
                let local = SIMD2<Float>(bounds.minX + unit.x * bounds.width,
                                         bounds.minZ + unit.y * bounds.length)
                if !closed || Self.contains(local, walls: walls) { candidates.append(unit) }
            }
        }
        points = candidates
    }

    /// Require endpoint connectivity before interpreting unordered wall segments as a perimeter.
    private static func isClosed(_ walls: [RoomPlanSnapshot.WallSegment]) -> Bool {
        guard walls.count >= 3 else { return false }
        let endpoints = walls.flatMap { [SIMD2<Float>($0.startX, $0.startZ), SIMD2<Float>($0.endX, $0.endZ)] }
        return endpoints.indices.allSatisfy { index in
            endpoints.indices.contains { other in
                other / 2 != index / 2 && distanceSquared(endpoints[index], endpoints[other]) < 0.15 * 0.15
            }
        }
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

    private static func distanceSquared(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let delta = a - b
        return delta.x * delta.x + delta.y * delta.y
    }
}
