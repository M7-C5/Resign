//
//  FurnitureEntityFactory.swift
//  Resign
//

import Foundation
import RealityKit
import UIKit
import simd

public final class FurnitureEntityFactory {
    public static func createEntity(for furniture: Furniture) -> Entity {
        let container = Entity()
        container.name = "Furniture_\(furniture.name)"
        container.position = SIMD3<Float>(furniture.positionX, furniture.positionY, furniture.positionZ)
        container.orientation = simd_quatf(angle: furniture.rotationYaw, axis: SIMD3<Float>(0, 1, 0))

        // If custom USDZ model exists at specified URL
        if let url = furniture.usdzURL, FileManager.default.fileExists(atPath: url.path) {
            if let customModel = try? Entity.load(contentsOf: url) {
                container.addChild(customModel)
                return container
            }
        }

        // Procedural bounding box fallback representing the detected furniture bounding volume
        let material = material(for: furniture.category)

        if furniture.name == "L-Shaped Desk" {
            let totalW = furniture.width
            let totalH = furniture.height
            let totalL = furniture.length
            let wingDepth = min(0.60, min(totalW, totalL) * 0.45)

            let mainMesh = MeshResource.generateBox(
                size: SIMD3<Float>(totalW, totalH, wingDepth),
                cornerRadius: 0.02
            )
            let mainWing = ModelEntity(mesh: mainMesh, materials: [material])
            mainWing.name = "MainWingMesh"
            mainWing.position = SIMD3<Float>(
                0,
                totalH / 2.0,
                -(totalL / 2.0) + (wingDepth / 2.0)
            )
            container.addChild(mainWing)

            let returnLength = max(totalL - wingDepth, 0.20)
            let returnMesh = MeshResource.generateBox(
                size: SIMD3<Float>(wingDepth, totalH, returnLength),
                cornerRadius: 0.02
            )
            let returnWing = ModelEntity(mesh: returnMesh, materials: [material])
            returnWing.name = "ReturnWingMesh"
            returnWing.position = SIMD3<Float>(
                (totalW / 2.0) - (wingDepth / 2.0),
                totalH / 2.0,
                wingDepth / 2.0
            )
            container.addChild(returnWing)
            return container
        }

        let mesh = MeshResource.generateBox(
            size: SIMD3<Float>(furniture.width, furniture.height, furniture.length),
            cornerRadius: 0.02
        )
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        modelEntity.name = "ModelMesh"
        // Offset Y so bottom of bounding box rests at Y = 0 (floor)
        modelEntity.position = SIMD3<Float>(0, furniture.height / 2.0, 0)

        container.addChild(modelEntity)
        return container
    }

    private static func material(for category: String) -> RealityKit.Material {
        let color: UIColor
        switch category.lowercased() {
        case "bed":
            color = UIColor(red: 0.35, green: 0.45, blue: 0.65, alpha: 1.0) // Slate Blue
        case "sofa":
            color = UIColor(red: 0.60, green: 0.45, blue: 0.35, alpha: 1.0) // Warm Leather / Camel
        case "desk", "table":
            color = UIColor(red: 0.50, green: 0.38, blue: 0.28, alpha: 1.0) // Walnut Wood
        case "chair":
            color = UIColor(red: 0.40, green: 0.50, blue: 0.45, alpha: 1.0) // Sage Green
        case "closet":
            color = UIColor(red: 0.30, green: 0.30, blue: 0.35, alpha: 1.0) // Charcoal Oak
        case "television":
            color = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) // Matte Black
        case "fireplace":
            color = UIColor(red: 0.45, green: 0.25, blue: 0.20, alpha: 1.0) // Terracotta Brick
        default:
            color = UIColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0) // Soft Gray
        }
        return SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)
    }
}
