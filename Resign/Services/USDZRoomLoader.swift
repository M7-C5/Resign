//
//  USDZRoomLoader.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation
import ModelIO
import simd

public enum USDZRoomLoaderError: Error, LocalizedError {
    case fileNotFound(String)
    case unreadableAsset(URL)
    case noMeshElementsFound
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "USDZ file could not be found at path: \(path)"
        case .unreadableAsset(let url):
            return "ModelIO failed to parse asset at: \(url.path)"
        case .noMeshElementsFound:
            return "No recognizable architectural meshes were found in the USDZ asset"
        }
    }
}

public final class USDZRoomLoader: Sendable {
    public init() {}

    /// Locates the bundled `MockRoom.usdz` across main bundle and test bundles.
    public static func findBundledMockRoomURL() -> URL? {
        if let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") {
            return url
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "MockRoom", withExtension: "usdz") {
                return url
            }
        }
        return nil
    }

    /// Locates the bundled `Room-2.usdz` across main bundle and test bundles.
    public static func findBundledRoom2URL() -> URL? {
        if let url = Bundle.main.url(forResource: "Room-2", withExtension: "usdz") {
            return url
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "Room-2", withExtension: "usdz") {
                return url
            }
        }
        return nil
    }

    /// Locates the bundled `Room.usdz` across main bundle and test bundles.
    public static func findBundledRoomURL() -> URL? {
        if let url = Bundle.main.url(forResource: "Room", withExtension: "usdz") {
            return url
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "Room", withExtension: "usdz") {
                return url
            }
        }
        return nil
    }

    /// Dynamically loads and parses a Room entity directly from a USDZ file URL.
    @MainActor
    public func loadRoom(from url: URL) throws -> Room {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw USDZRoomLoaderError.fileNotFound(url.path)
        }

        let asset = MDLAsset(url: url)
        guard asset.count > 0 else {
            throw USDZRoomLoaderError.unreadableAsset(url)
        }

        var allObjects: [MDLObject] = []
        func collect(object: MDLObject) {
            allObjects.append(object)
            for i in 0..<object.children.count {
                collect(object: object.children[i])
            }
        }
        for i in 0..<asset.count {
            collect(object: asset.object(at: i))
        }

        // Prefer leaf meshes over hierarchical container group nodes ending in _grp
        let leafCandidates = allObjects.filter { !$0.name.hasSuffix("_grp") }

        // 1. Calculate dominant wall tilt and un-tilted room dimensions
        let wallObjects = leafCandidates.filter { $0.name.lowercased().hasPrefix("wall") }
        var wallLengths: [Float] = []
        var wallAngles: [Float] = []

        func normalizeQuarterTurn(_ angle: Float) -> Float {
            let quarter = Float.pi / 2.0
            var rem = angle.truncatingRemainder(dividingBy: quarter)
            if rem > quarter / 2.0 { rem -= quarter }
            else if rem < -quarter / 2.0 { rem += quarter }
            return rem
        }

        for w in wallObjects {
            let t = w.transform?.matrix ?? matrix_identity_float4x4
            let forward = simd_normalize(simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z))
            let len = simd_length(simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z))
            if len > 0.5 { wallLengths.append(len) }
            let a = atan2(forward.z, forward.x)
            wallAngles.append(normalizeQuarterTurn(a))
        }

        wallAngles.sort()
        let dominantTilt = wallAngles.isEmpty ? 0.0 : wallAngles[wallAngles.count / 2]

        let cosT = cos(dominantTilt)
        let sinT = sin(dominantTilt)
        func rotateY(_ v: simd_float3) -> simd_float3 {
            return simd_float3(v.x * cosT + v.z * sinT, v.y, -v.x * sinT + v.z * cosT)
        }

        var roomWidth: Float = 5.0
        var roomLength: Float = 4.2
        var roomHeight: Float = 2.6
        var roomCenterX: Float = 0.0
        var roomCenterZ: Float = 0.0
        var floorLevelY: Float = 0.0

        if let floor = leafCandidates.first(where: { $0.name.lowercased().hasPrefix("floor") }) ?? allObjects.first(where: { $0.name.lowercased().hasPrefix("floor") }),
           let bounds = computeBounds(for: floor) {
            let rawDx = bounds.max.x - bounds.min.x
            let rawDy = bounds.max.y - bounds.min.y
            let rawDz = bounds.max.z - bounds.min.z

            let rawCenter = (bounds.min + bounds.max) * 0.5
            let rotCenter = rotateY(rawCenter)
            roomCenterX = rotCenter.x
            roomCenterZ = rotCenter.z
            floorLevelY = bounds.min.y

            let cosT = cos(dominantTilt)
            let sinT = abs(sin(dominantTilt))
            let denom = cosT * cosT - sinT * sinT

            let extentX = rawDx
            let extentZ = (rawDy < 0.05) ? rawDz : max(rawDy, rawDz)

            if denom > 0.05 {
                let unTiltedW = abs((extentX * cosT - extentZ * sinT) / denom)
                let unTiltedL = abs((extentZ * cosT - extentX * sinT) / denom)
                roomWidth = max(unTiltedW, 3.0)
                roomLength = max(unTiltedL, 3.0)
            } else {
                roomWidth = max(extentX, 3.0)
                roomLength = max(extentZ, 3.0)
            }
        }

        if let ceiling = leafCandidates.first(where: { $0.name.lowercased().hasPrefix("ceiling") }) ?? allObjects.first(where: { $0.name.lowercased().hasPrefix("ceiling") }),
           let bounds = computeBounds(for: ceiling) {
            roomHeight = max(bounds.min.y - floorLevelY, 2.4)
        } else {
            let walls = leafCandidates.filter { $0.name.lowercased().hasPrefix("wall") }
            if let firstWall = walls.first, let bounds = computeBounds(for: firstWall) {
                let h = bounds.max.y - bounds.min.y
                if h > 1.5 { roomHeight = h }
            }
        }

        let room = Room(
            name: "Scanned USDZ Room",
            longitude: -122.4194,
            latitude: 37.7749,
            compass: 90.0,
            length: roomLength,
            width: roomWidth,
            height: roomHeight
        )

        // 2. Extract Openings (Window & Door)
        var openings: [RoomOpening] = []
        for obj in leafCandidates {
            let lower = obj.name.lowercased()
            if lower.hasPrefix("window") {
                if let b = computeBounds(for: obj) {
                    let w = max(b.max.x - b.min.x, b.max.z - b.min.z)
                    let h = b.max.y - b.min.y
                    let rawCenter = (b.min + b.max) * 0.5
                    let rotCenter = rotateY(rawCenter)
                    let opening = RoomOpening(
                        type: "window",
                        posX: rotCenter.x - roomCenterX,
                        posY: rotCenter.y - floorLevelY,
                        posZ: rotCenter.z - roomCenterZ,
                        width: max(w, 0.8),
                        height: max(h, 1.0)
                    )
                    openings.append(opening)
                }
            } else if lower.hasPrefix("door") {
                if let b = computeBounds(for: obj) {
                    let w = max(b.max.x - b.min.x, b.max.z - b.min.z)
                    let h = b.max.y - b.min.y
                    let rawCenter = (b.min + b.max) * 0.5
                    let rotCenter = rotateY(rawCenter)
                    let opening = RoomOpening(
                        type: "door",
                        posX: rotCenter.x - roomCenterX,
                        posY: rotCenter.y - floorLevelY,
                        posZ: rotCenter.z - roomCenterZ,
                        width: max(w, 0.8),
                        height: max(h, 2.0)
                    )
                    openings.append(opening)
                }
            }
        }
        room.openings = openings

        // 3. Extract Furnitures
        let furnitureTargets: [(name: String, category: String)] = [
            ("Bed", "bed"),
            ("Desk", "desk"),
            ("Chair", "chair"),
            ("Sofa", "sofa"),
            ("Closet", "closet"),
            ("TV", "television")
        ]

        let layout = Layout(name: "Scanned 3D Layout", usdzURL: url)
        var furnitures: [Furniture] = []

        for target in furnitureTargets {
            if let obj = leafCandidates.first(where: {
                $0.name.localizedCaseInsensitiveContains(target.name) ||
                $0.name.localizedCaseInsensitiveContains(target.category) ||
                (target.category == "desk" && $0.name.localizedCaseInsensitiveContains("table")) ||
                (target.category == "closet" && $0.name.localizedCaseInsensitiveContains("storage"))
            }) ?? allObjects.first(where: {
                $0.name.localizedCaseInsensitiveContains(target.name) ||
                $0.name.localizedCaseInsensitiveContains(target.category) ||
                (target.category == "desk" && $0.name.localizedCaseInsensitiveContains("table")) ||
                (target.category == "closet" && $0.name.localizedCaseInsensitiveContains("storage"))
            }),
               let b = computeBounds(for: obj) {
                let dx = b.max.x - b.min.x
                let dy = b.max.y - b.min.y
                let dz = b.max.z - b.min.z
                let rawCenter = (b.min + b.max) * 0.5
                let rotCenter = rotateY(rawCenter)
                let cx = rotCenter.x - roomCenterX
                let cz = rotCenter.z - roomCenterZ

                let item = Furniture(
                    name: target.name,
                    category: target.category,
                    texture: "default",
                    positionX: cx,
                    positionY: 0.0,
                    positionZ: cz,
                    rotationYaw: 0.0,
                    length: max(dz, 0.3),
                    width: max(dx, 0.3),
                    height: max(dy, 0.3),
                    isArchived: false,
                    usdzURL: nil
                )
                furnitures.append(item)
            }
        }

        layout.furnitures = furnitures
        room.layouts = [layout]

        return room
    }

    /// Computes recursive axis-aligned world bounds encompassing all child meshes.
    private func computeBounds(for object: MDLObject) -> (min: simd_float3, max: simd_float3)? {
        var minPt = simd_float3(repeating: .infinity)
        var maxPt = simd_float3(repeating: -.infinity)
        var foundMesh = false

        func inspect(_ obj: MDLObject) {
            if let mesh = obj as? MDLMesh {
                let b = mesh.boundingBox(atTime: 0.0)
                if b.maxBounds.x > b.minBounds.x || b.maxBounds.y > b.minBounds.y || b.maxBounds.z > b.minBounds.z {
                    minPt = simd_min(minPt, b.minBounds)
                    maxPt = simd_max(maxPt, b.maxBounds)
                    foundMesh = true
                }
            }
            for i in 0..<obj.children.count {
                inspect(obj.children[i])
            }
        }

        inspect(object)
        return foundMesh ? (minPt, maxPt) : nil
    }
}
