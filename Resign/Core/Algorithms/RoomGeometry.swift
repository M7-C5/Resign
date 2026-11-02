//
//  RoomGeometry.swift
//  Resign
//
//  Single source of truth for walls, openings and furniture orientation. The clearance
//  engine, validator, solver, tools and the 3D scene all rely on these conventions.
//
//  Convention: a piece's mesh is authored at `rotationYaw == 0`. `width` runs along X and
//  `length` along Z. Each category has a "back" (the side that goes against a wall, or the
//  headboard / backrest side). Positive yaw rotates about +Y exactly like RealityKit:
//  (x, z) -> (x cos t + z sin t, -x sin t + z cos t).
//

import Foundation

public enum RoomWall: String, CaseIterable, Sendable {
    case north, south, east, west

    /// Opposite wall in the room.
    public var opposite: RoomWall {
        switch self {
        case .north: return .south
        case .south: return .north
        case .east: return .west
        case .west: return .east
        }
    }

    /// Unit vector from the room centre toward the wall (north is -Z, east is +X).
    public var towardWall: (x: Float, z: Float) {
        switch self {
        case .north: return (0, -1)
        case .south: return (0, 1)
        case .east: return (1, 0)
        case .west: return (-1, 0)
        }
    }

    /// Wall closest to a point; correct for non-square rooms.
    public static func nearest(toX x: Float, z: Float, halfWidth: Float, halfLength: Float) -> RoomWall {
        let distances: [(RoomWall, Float)] = [
            (.north, abs(z + halfLength)),
            (.south, abs(halfLength - z)),
            (.east, abs(halfWidth - x)),
            (.west, abs(x + halfWidth))
        ]
        return distances.min { $0.1 < $1.1 }!.0
    }
}

public enum FurnitureOrientation {
    /// Direction of the item's back at yaw 0, matching the authored meshes.
    public static func nativeBack(forCategory category: String) -> (x: Float, z: Float) {
        switch category.lowercased() {
        case "bed", "television", "tv": return (0, -1)   // headboard / screen back toward north
        case "desk": return (1, 0)                        // desk back toward east
        case "chair": return (-1, 0)                      // backrest toward west
        case "sofa": return (0, 1)                        // backrest toward south
        case "closet", "wardrobe": return (-1, 0)         // doors face east
        default: return (0, -1)
        }
    }

    public static func rotate(_ v: (x: Float, z: Float), yaw: Float) -> (x: Float, z: Float) {
        (v.x * cos(yaw) + v.z * sin(yaw), -v.x * sin(yaw) + v.z * cos(yaw))
    }

    /// Quarter-turn yaw whose back points along `direction`.
    public static func yaw(forCategory category: String, backTowards direction: (x: Float, z: Float)) -> Float {
        let back = nativeBack(forCategory: category)
        for quarter in 0..<4 {
            let yaw = Float(quarter) * .pi / 2
            let r = rotate(back, yaw: yaw)
            if abs(r.x - direction.x) < 0.01 && abs(r.z - direction.z) < 0.01 { return yaw }
        }
        return 0
    }

    /// Direction the piece faces (opposite its back).
    public static func frontDirection(of furniture: Furniture) -> (x: Float, z: Float) {
        let back = rotate(nativeBack(forCategory: furniture.category), yaw: furniture.rotationYaw)
        return (-back.x, -back.z)
    }

    /// The room wall the piece's back points towards, based on authored nativeBack and yaw rotation.
    public static func wallBehind(forCategory category: String, yaw: Float) -> RoomWall {
        let back = rotate(nativeBack(forCategory: category), yaw: yaw)
        if abs(back.x) > abs(back.z) {
            return back.x > 0 ? .east : .west
        } else {
            return back.z > 0 ? .south : .north
        }
    }

    public static func wallBehind(_ furniture: Furniture) -> RoomWall {
        wallBehind(forCategory: furniture.category, yaw: furniture.rotationYaw)
    }
}
