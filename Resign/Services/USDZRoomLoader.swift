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

        // 1. Extract Room Dimensions from Floor / Ceiling / Walls
        var roomWidth: Float = 5.0
        var roomLength: Float = 4.2
        var roomHeight: Float = 2.6

        if let floor = allObjects.first(where: { $0.name.lowercased() == "floor" }),
           let bounds = computeBounds(for: floor) {
            roomWidth = bounds.max.x - bounds.min.x
            roomLength = bounds.max.z - bounds.min.z
        }

        if let ceiling = allObjects.first(where: { $0.name.lowercased() == "ceiling" }),
           let bounds = computeBounds(for: ceiling) {
            roomHeight = bounds.min.y
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
        for obj in allObjects {
            let lower = obj.name.lowercased()
            if lower == "window" {
                if let b = computeBounds(for: obj) {
                    let w = max(b.max.x - b.min.x, b.max.z - b.min.z)
                    let h = b.max.y - b.min.y
                    let opening = RoomOpening(
                        type: "window",
                        posX: (b.min.x + b.max.x) / 2.0,
                        posY: (b.min.y + b.max.y) / 2.0,
                        posZ: (b.min.z + b.max.z) / 2.0,
                        width: w,
                        height: h
                    )
                    openings.append(opening)
                }
            } else if lower == "door" {
                if let b = computeBounds(for: obj) {
                    let w = max(b.max.x - b.min.x, b.max.z - b.min.z)
                    let h = b.max.y - b.min.y
                    let opening = RoomOpening(
                        type: "door",
                        posX: (b.min.x + b.max.x) / 2.0,
                        posY: (b.min.y + b.max.y) / 2.0,
                        posZ: (b.min.z + b.max.z) / 2.0,
                        width: w,
                        height: h
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
            if let obj = allObjects.first(where: { $0.name == target.name }),
               let b = computeBounds(for: obj) {
                let dx = b.max.x - b.min.x
                let dy = b.max.y - b.min.y
                let dz = b.max.z - b.min.z
                let cx = (b.min.x + b.max.x) / 2.0
                let cy = (b.min.y + b.max.y) / 2.0
                let cz = (b.min.z + b.max.z) / 2.0

                let item = Furniture(
                    name: target.name,
                    category: target.category,
                    texture: "default",
                    positionX: cx,
                    positionY: cy,
                    positionZ: cz,
                    rotationYaw: 0.0,
                    length: dz,
                    width: dx,
                    height: dy,
                    isArchived: false,
                    usdzURL: url
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
            let b = obj.boundingBox(atTime: 0.0)
            if b.maxBounds.x > b.minBounds.x || b.maxBounds.y > b.minBounds.y || b.maxBounds.z > b.minBounds.z {
                minPt = simd_min(minPt, b.minBounds)
                maxPt = simd_max(maxPt, b.maxBounds)
                foundMesh = true
            }
            for i in 0..<obj.children.count {
                inspect(obj.children[i])
            }
        }

        inspect(object)
        return foundMesh ? (minPt, maxPt) : nil
    }
}
