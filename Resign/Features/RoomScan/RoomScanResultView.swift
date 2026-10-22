//
//  RoomScanResultView.swift
//  Resign
//

import SwiftUI
import RealityKit
import SwiftData
import QuickLook
import UIKit
import simd

public struct RoomScanResultView: View {
    public let roomId: UUID
    public let onScanAgain: () -> Void

    @Query private var rooms: [Room]
    @State private var quickLookURL: URL? = nil

    public init(roomId: UUID, onScanAgain: @escaping () -> Void) {
        self.roomId = roomId
        self.onScanAgain = onScanAgain
        let targetId = roomId
        _rooms = Query(filter: #Predicate<Room> { $0.id == targetId })
    }

    private var room: Room? {
        rooms.first
    }

    private var layout: Layout? {
        room?.layouts.first
    }

    public var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()

            if let room, let layout {
                VStack(spacing: 0) {
                    // Top Metrics Bar
                    headerBar(room: room)

                    // Interactive 3D RealityKit Dollhouse Viewport
                    Room3DRealityViewport(room: room, layout: layout)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom Details & Action Card
                    bottomCard(room: room, layout: layout)
                }
            } else {
                ProgressView("Loading 3D Room...")
                    .foregroundStyle(.white)
            }
        }
        .quickLookPreview($quickLookURL)
    }

    private func headerBar(room: Room) -> some View {
        VStack(spacing: 4) {
            Text("Scan Complete")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.green.opacity(0.15), in: Capsule())

            Text(room.name)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text(String(format: "%.2fm (W) × %.2fm (L) • Height: %.2fm", room.width, room.length, room.height))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func bottomCard(room: Room, layout: Layout) -> some View {
        VStack(spacing: 16) {
            // Metrics Summary Row
            HStack(spacing: 12) {
                metricChip(
                    icon: "door.left.hand.open",
                    label: "\(room.openings.count) Openings"
                )

                metricChip(
                    icon: "bed.double.fill",
                    label: "\(layout.furnitures.count) Furnitures"
                )

                Spacer()
            }
            .padding(.horizontal, 20)

            // Detected Furniture Items List
            if !layout.furnitures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(layout.furnitures) { item in
                            furnitureCard(for: item)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // QuickLook & Export Actions Row
            if let url = layout.usdzURL {
                HStack(spacing: 12) {
                    Button {
                        quickLookURL = url
                    } label: {
                        Label("AR QuickLook", systemImage: "arkit")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }

                    ShareLink(item: url) {
                        Label("Export 3D", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
            }

            // Primary Scan Again Action
            Button(action: onScanAgain) {
                Label("Scan Another Room", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .padding(.top, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .ignoresSafeArea(edges: .bottom)
    }

    private func metricChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func furnitureCard(for item: Furniture) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.category.capitalized)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(item.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(String(format: "%.2fm × %.2fm", item.width, item.length))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 140)
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct Room3DRealityViewport: View {
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

                    roomContent.addChild(roomShell)
                }
            }

            // 2. Load all detected, grounded, and plaster-snapped furniture objects
            for furniture in layout.furnitures {
                let entity = FurnitureEntityFactory.createEntity(for: furniture)
                roomContent.addChild(entity)
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
