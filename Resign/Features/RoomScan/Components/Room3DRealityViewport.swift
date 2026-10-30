//
//  Room3DRealityViewport.swift
//  Resign
//

import SwiftUI
import RealityKit
import UIKit
import simd

struct Room3DRealityViewport: View {
    let room: Room
    let layout: Layout

    @State private var rotationYaw: Float = 0.0
    @State private var dragStartYaw: Float = 0.0
    @State private var pitchAngle: Float = 0.45
    @State private var dragStartPitch: Float = 0.45
    @State private var zoomScale: Float = 1.0
    @State private var baseZoomScale: Float = 1.0

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "DollhouseRoot"

            let roomContent = Entity()
            roomContent.name = "RoomContent"

            let snap = room.planSnapshotData.flatMap {
                try? JSONDecoder().decode(RoomPlanSnapshot.self, from: $0)
            }

            // 1. Load Apple's native parametric room shell (Room.usdz)
            if let url = layout.usdzURL, FileManager.default.fileExists(atPath: url.path) {
                if let roomShell = try? await Entity(contentsOf: url) {
                    roomShell.name = "RoomShell"

                    // Disable RoomPlan's default wireframe bounding boxes so Resign's sanitized 3D models render
                    if let objectGrp = roomShell.findEntity(named: "Object_grp") {
                        objectGrp.isEnabled = false
                    }

                    // Apply warm architectural PBR materials to drywall and hardwood floor
                    applyArchitecturalStyling(to: roomShell)

                    let captureSpace = Entity()
                    captureSpace.name = "CaptureSpace"
                    if let snap {
                        let effectiveYaw = snap.yawRadians
                        let inverseYaw = simd_quatf(angle: -effectiveYaw, axis: [0, 1, 0])
                        captureSpace.orientation = inverseYaw
                        captureSpace.addChild(roomShell)
                        let floorY = snap.floorLevel ?? (roomShell.findEntity(named: "Floor_grp")?.visualBounds(relativeTo: captureSpace).center.y ?? 0)
                        captureSpace.position = inverseYaw.act([-snap.centerX, -floorY, -snap.centerZ])
                    } else {
                        captureSpace.addChild(roomShell)
                    }

                    roomContent.addChild(captureSpace)
                }
            }

            // 2. Load all detected, grounded, and plaster-snapped furniture objects
            // Only add synthesized entities if the loaded USDZ doesn't already contain modeled furniture
            let hasModeledFurniture = (roomContent.findEntity(named: "Furniture") != nil)
            if !hasModeledFurniture {
                for furniture in layout.furnitures {
                    var posX = furniture.positionX
                    var posY = furniture.positionY
                    var posZ = furniture.positionZ
                    var yaw = furniture.rotationYaw

                    if let snap {
                        let dToSnapCenter = hypot(posX - snap.centerX, posZ - snap.centerZ)
                        let dToOrigin = hypot(posX, posZ)
                        let isCloserToSnapCenter = (abs(snap.centerX) > 0.2 || abs(snap.centerZ) > 0.2) && (dToSnapCenter + 0.3 < dToOrigin)
                        let isBelowFloor = posY < -0.05

                        if isCloserToSnapCenter || isBelowFloor {
                            let localPos = snap.localCoordinates(worldX: posX, worldZ: posZ)
                            posX = localPos.x
                            posZ = localPos.y
                            yaw = snap.localYaw(yaw)
                            if let floorLvl = snap.floorLevel {
                                posY = max(0.0, posY - floorLvl)
                            } else {
                                posY = max(0.0, posY)
                            }
                        }
                    }

                    if furniture.category.lowercased() == "chair" || furniture.category.lowercased() == "sofa" {
                        posY = 0.0
                    } else {
                        posY = max(0.0, posY)
                    }

                    let displayItem = Furniture(
                        id: furniture.id,
                        name: furniture.name,
                        category: furniture.category,
                        positionX: posX,
                        positionY: posY,
                        positionZ: posZ,
                        rotationYaw: yaw,
                        length: furniture.length,
                        width: furniture.width,
                        height: furniture.height,
                        usdzURL: furniture.usdzURL
                    )
                    let entity = FurnitureEntityFactory.createEntity(for: displayItem)
                    roomContent.addChild(entity)
                }
            }

            // 3. Directional sun lighting with real-time shadow casting
            let sun = DirectionalLight()
            sun.light.intensity = 2000
            sun.light.color = .init(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0)
            sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 12.0, depthBias: 1.0)
            sun.position = SIMD3<Float>(3.5, 5.0, 3.5)
            sun.look(at: .zero, from: sun.position, relativeTo: nil)
            root.addChild(sun)

            root.addChild(roomContent)

            // Position the entire dollhouse in front of the default camera at a comfortable viewing distance
            let maxDim = max(room.width, room.length, 3.0)
            root.position = SIMD3<Float>(0, -0.4, -maxDim * 1.3)

            content.add(root)
        } update: { content in
            if let root = content.entities.first(where: { $0.name == "DollhouseRoot" }) {
                let yawQuat = simd_quatf(angle: rotationYaw, axis: SIMD3<Float>(0, 1, 0))
                let pitchQuat = simd_quatf(angle: pitchAngle, axis: SIMD3<Float>(1, 0, 0))
                root.orientation = pitchQuat * yawQuat
                root.scale = SIMD3<Float>(repeating: zoomScale)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    rotationYaw = dragStartYaw + Float(value.translation.width) * 0.008
                    let newPitch = dragStartPitch + Float(value.translation.height) * 0.005
                    pitchAngle = min(max(newPitch, 0.05), 1.5)
                }
                .onEnded { _ in
                    dragStartYaw = rotationYaw
                    dragStartPitch = pitchAngle
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { scale in
                    zoomScale = max(0.3, min(3.0, baseZoomScale * Float(scale)))
                }
                .onEnded { _ in
                    baseZoomScale = zoomScale
                }
        )
    }

    private func applyArchitecturalStyling(to roomShell: Entity) {
        let wallMaterial = SimpleMaterial(
            color: UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1.0),
            roughness: 0.85,
            isMetallic: false
        )
        let floorMaterial = SimpleMaterial(
            color: UIColor(red: 0.76, green: 0.60, blue: 0.44, alpha: 1.0),
            roughness: 0.45,
            isMetallic: false
        )

        // Style floors with warm natural oak
        if let floorGrp = roomShell.findEntity(named: "Floor_grp") {
            assignMaterial(floorMaterial, toDescendantsOf: floorGrp)
        }

        // Style walls with matte drywall while preserving door and window frames
        if let archGrp = roomShell.findEntity(named: "Arch_grp") {
            for child in archGrp.children where child.name.lowercased().contains("wall") {
                assignMaterial(
                    wallMaterial,
                    toDescendantsOf: child,
                    filter: { entity in
                        let name = entity.name.lowercased()
                        return !name.contains("door") && !name.contains("window")
                    }
                )
            }
        }
    }

    private func assignMaterial(
        _ material: RealityKit.Material,
        toDescendantsOf entity: Entity,
        filter: ((Entity) -> Bool)? = nil
    ) {
        if filter?(entity) ?? true {
            if var model = entity.components[ModelComponent.self] {
                model.materials = [material]
                entity.components.set(model)
            }
        }
        for child in entity.children {
            assignMaterial(material, toDescendantsOf: child, filter: filter)
        }
    }
}
