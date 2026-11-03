//
//  LayoutValidationEngine.swift
//  Resign
//
//  Deterministic oracle for "is this layout physically sound?". Shared by the solver tests,
//  the Foundation Model tools and any UI that wants to show verified facts.
//

import Foundation

public struct ItemOverlap: Equatable, Sendable {
    public let idA: UUID
    public let idB: UUID
    public let nameA: String
    public let nameB: String
    /// Smaller of the two penetration depths, in centimetres.
    public let depthCm: Double
}

public struct OutOfBoundsItem: Equatable, Sendable {
    public let id: UUID
    public let name: String
}

public struct LayoutValidationReport: Sendable {
    public var overlaps: [ItemOverlap]
    public var outOfBounds: [OutOfBoundsItem]
    /// Items standing between the TV and the sofa.
    public var sightlineBlockers: [UUID]
    public var violations: [SpatialViolation]

    public var criticalViolations: [SpatialViolation] { violations.filter { $0.severity == .critical } }

    public var isClean: Bool {
        overlaps.isEmpty && outOfBounds.isEmpty && sightlineBlockers.isEmpty && criticalViolations.isEmpty
    }

    /// Compact, model-friendly summary (centimetres only).
    public var summary: String {
        "overlaps: \(overlaps.count), out of bounds: \(outOfBounds.count), critical violations: \(criticalViolations.count), "
        + "warnings: \(violations.count - criticalViolations.count), tv sightline blocked: \(sightlineBlockers.isEmpty ? "no" : "yes")"
    }
}

public struct LayoutValidationEngine: Sendable {
    public static let overlapToleranceMeters: Float = 0.01
    public static let sightlineHalfWidthMeters: Float = 0.30

    private let clearance = SpatialClearanceEngine()

    public init() {}

    public func validate(room: Room, furnitures: [Furniture]) -> LayoutValidationReport {
        let active = furnitures.filter { !$0.isArchived }
        let doors = room.openings.filter { $0.type.lowercased() == "door" }

        var violations: [SpatialViolation] = []
        violations += clearance.checkWalkwayClearances(furnitures: active, roomLength: room.length, roomWidth: room.width)
        violations += clearance.checkDeskClearance(furnitures: active, roomLength: room.length, roomWidth: room.width)
        violations += clearance.checkBedClearance(furnitures: active, roomLength: room.length, roomWidth: room.width)
        violations += clearance.checkDoorSwing(furnitures: active, doors: doors, roomWidth: room.width, roomLength: room.length)

        return LayoutValidationReport(
            overlaps: overlaps(in: active),
            outOfBounds: outOfBounds(in: active, roomWidth: room.width, roomLength: room.length),
            sightlineBlockers: sightlineBlockers(in: active),
            violations: violations
        )
    }

    public func overlaps(in furnitures: [Furniture]) -> [ItemOverlap] {
        var result: [ItemOverlap] = []
        let items = furnitures.filter { !$0.isArchived }
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                let a = clearance.boundingBox(for: items[i])
                let b = clearance.boundingBox(for: items[j])
                let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                let overlapZ = min(a.maxZ, b.maxZ) - max(a.minZ, b.minZ)
                if overlapX > Self.overlapToleranceMeters && overlapZ > Self.overlapToleranceMeters {
                    result.append(
                        ItemOverlap(
                            idA: items[i].id, idB: items[j].id,
                            nameA: items[i].name, nameB: items[j].name,
                            depthCm: Double(min(overlapX, overlapZ) * 100)
                        )
                    )
                }
            }
        }
        return result
    }

    public func outOfBounds(in furnitures: [Furniture], roomWidth: Float, roomLength: Float) -> [OutOfBoundsItem] {
        let halfW = roomWidth / 2 + Self.overlapToleranceMeters
        let halfL = roomLength / 2 + Self.overlapToleranceMeters
        return furnitures.filter { !$0.isArchived }.compactMap { item in
            let box = clearance.boundingBox(for: item)
            let inside = box.minX >= -halfW && box.maxX <= halfW && box.minZ >= -halfL && box.maxZ <= halfL
            return inside ? nil : OutOfBoundsItem(id: item.id, name: item.name)
        }
    }

    /// Items whose footprint (inflated by the corridor half-width) is crossed by the TV→sofa line.
    public func sightlineBlockers(in furnitures: [Furniture]) -> [UUID] {
        let active = furnitures.filter { !$0.isArchived }
        guard let tv = active.first(where: { Self.isTV($0) }),
              let sofa = active.first(where: { $0.category.lowercased() == "sofa" }) else { return [] }

        let p0 = (x: tv.positionX, z: tv.positionZ)
        let p1 = (x: sofa.positionX, z: sofa.positionZ)
        let pad = Self.sightlineHalfWidthMeters

        return active.compactMap { item in
            guard item.id != tv.id, item.id != sofa.id else { return nil }
            let box = clearance.boundingBox(for: item)
            let inflated = SpatialClearanceEngine.BoundingBox2D(
                minX: box.minX - pad, maxX: box.maxX + pad, minZ: box.minZ - pad, maxZ: box.maxZ + pad
            )
            return Self.segment(from: p0, to: p1, crosses: inflated) ? item.id : nil
        }
    }

    static func isTV(_ f: Furniture) -> Bool {
        f.category.lowercased() == "television" || f.category.lowercased() == "tv"
    }

    /// Liang–Barsky style slab test.
    static func segment(
        from p0: (x: Float, z: Float),
        to p1: (x: Float, z: Float),
        crosses box: SpatialClearanceEngine.BoundingBox2D
    ) -> Bool {
        var tMin: Float = 0
        var tMax: Float = 1
        let axes: [(origin: Float, delta: Float, lo: Float, hi: Float)] = [
            (p0.x, p1.x - p0.x, box.minX, box.maxX),
            (p0.z, p1.z - p0.z, box.minZ, box.maxZ)
        ]
        for axis in axes {
            if abs(axis.delta) < 1e-6 {
                if axis.origin < axis.lo || axis.origin > axis.hi { return false }
            } else {
                var t1 = (axis.lo - axis.origin) / axis.delta
                var t2 = (axis.hi - axis.origin) / axis.delta
                if t1 > t2 { swap(&t1, &t2) }
                tMin = max(tMin, t1)
                tMax = min(tMax, t2)
                if tMin > tMax { return false }
            }
        }
        return true
    }
}
