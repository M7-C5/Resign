//
//  Studio3DSuggestionView.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import SwiftUI
import RealityKit
import simd
import CoreGraphics

@MainActor
public struct Studio3DSuggestionView: View {
    @Bindable public var viewModel: Studio3DViewModel
    public var usdzURL: URL?
    public var showsHUD: Bool

    // 45° Dollhouse Default Perspective
    // Pitch ~37 degrees looking down into room, Yaw ~ -32 degrees angled
    private static let defaultPitch: Float = 0.65
    private static let defaultYaw: Float = -0.55
    private static let defaultScale: Float = 0.38

    @State private var pitch: Float = Studio3DSuggestionView.defaultPitch
    @State private var yaw: Float = Studio3DSuggestionView.defaultYaw
    @State private var zoomScale: Float = Studio3DSuggestionView.defaultScale

    @State private var dragStartPitch: Float = Studio3DSuggestionView.defaultPitch
    @State private var dragStartYaw: Float = Studio3DSuggestionView.defaultYaw

    @State private var loadError: String? = nil

    @MainActor
    public init(viewModel: Studio3DViewModel, usdzURL: URL? = nil, showsHUD: Bool = false) {
        self.viewModel = viewModel
        self.usdzURL = usdzURL ?? USDZRoomLoader.findBundledMockRoomURL()
        self.showsHUD = showsHUD
    }

    @MainActor
    public init(usdzURL: URL? = nil, showsHUD: Bool = false) {
        self.init(viewModel: Studio3DViewModel(), usdzURL: usdzURL, showsHUD: showsHUD)
    }

    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if let url = usdzURL {
                RealityView { content in
                    do {
                        setupStudioLighting(in: content)

                        let entity = try await Entity(contentsOf: url)
                        entity.name = "RoomRoot"
                        entity.position = [0, -0.45, -2.7]
                        entity.scale = simd_float3(repeating: zoomScale)
                        applyOrientation(to: entity)
                        syncViolationOverlay(on: entity)
                        syncFurniturePositions(on: entity, animated: false)

                        if let iblEntity = content.entities.first(where: { $0.name == "StudioIBL" }) {
                            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
                        }

                        content.add(entity)
                    } catch {
                        self.loadError = "RealityKit load error: \(error.localizedDescription)"
                    }
                } update: { content in
                    if let entity = content.entities.first(where: { $0.name == "RoomRoot" }) {
                        entity.scale = simd_float3(repeating: zoomScale)
                        applyOrientation(to: entity)
                        syncViolationOverlay(on: entity)
                        syncFurniturePositions(on: entity, animated: false)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            // Natural orbit rotation around room center
                            yaw = dragStartYaw + Float(value.translation.width) * 0.007
                            let newPitch = dragStartPitch + Float(value.translation.height) * 0.007
                            // Clamp pitch so room doesn't flip upside-down or clip below floor
                            pitch = min(max(newPitch, 0.15), 1.50)
                        }
                        .onEnded { _ in
                            dragStartYaw = yaw
                            dragStartPitch = pitch
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let target = zoomScale * Float(value.magnification)
                            zoomScale = min(max(target, 0.20), 0.75)
                        }
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("MockRoom.usdz not located in bundle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Top HUD Overlay (only when showsHUD is true)
            if showsHUD {
                VStack {
                    topHUD
                    violationLegend
                    Spacer()
                    bottomPerspectiveBar
                }
            }
        }
    }

    // MARK: - Subviews

    private var violationLegend: some View {
        Group {
            if !viewModel.violationMarkers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $viewModel.showViolations) {
                        Text("Show violations (\(violationSummaries.count))")
                            .font(.caption).bold()
                    }
                    .toggleStyle(.switch)

                    if viewModel.showViolations {
                        ForEach(violationSummaries, id: \.ruleId) { summary in
                            HStack(spacing: 7) {
                                Text(summary.ruleId)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(summary.swiftUIColor, in: RoundedRectangle(cornerRadius: 4))

                                Text("\(summary.title) \u{2022} \(Int(summary.measuredCm.rounded())) / \(Int(summary.requiredCm.rounded())) cm")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// One legend row per rule (worst case first), regardless of how many items it touches.
    private var violationSummaries: [ViolationMarker] {
        var seen = Set<String>()
        return viewModel.violationMarkers
            .sorted { $0.severity == .critical && $1.severity != .critical }
            .filter { seen.insert($0.ruleId).inserted }
    }

    private var topHUD: some View {
        HStack {
            Label("USDZ 3D Studio", systemImage: "cube.transparent.fill")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            if !viewModel.highlightedFurnitureIDs.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("\(viewModel.highlightedFurnitureIDs.count) Clashes Highlighted")
                        .font(.caption).bold()
                    Button("Clear") {
                        viewModel.clearHighlights()
                    }
                    .font(.caption2).buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
        .padding()
    }

    private var bottomPerspectiveBar: some View {
        VStack(spacing: 8) {
            Text("Drag to orbit • Pinch to zoom")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())

            HStack(spacing: 10) {
                perspectiveButton(title: "45° Dollhouse", icon: "square.3.layers.3d.down.right") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pitch = Studio3DSuggestionView.defaultPitch
                        yaw = Studio3DSuggestionView.defaultYaw
                        zoomScale = Studio3DSuggestionView.defaultScale
                        dragStartPitch = pitch
                        dragStartYaw = yaw
                    }
                }

                perspectiveButton(title: "Top-Down", icon: "viewfinder") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pitch = 1.48 // Direct downward view looking through invisible ceiling
                        yaw = 0.0
                        zoomScale = 0.36
                        dragStartPitch = pitch
                        dragStartYaw = yaw
                    }
                }

                perspectiveButton(title: "East Window", icon: "sun.max") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pitch = 0.45
                        yaw = -Float.pi / 2.0
                        zoomScale = 0.40
                        dragStartPitch = pitch
                        dragStartYaw = yaw
                    }
                }

                perspectiveButton(title: "Reset", icon: "arrow.counterclockwise") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pitch = Studio3DSuggestionView.defaultPitch
                        yaw = Studio3DSuggestionView.defaultYaw
                        zoomScale = Studio3DSuggestionView.defaultScale
                        dragStartPitch = pitch
                        dragStartYaw = yaw
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func perspectiveButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Studio Lighting

    private func setupStudioLighting(in content: RealityViewCameraContent) {
        guard !content.entities.contains(where: { $0.name == "StudioIBL" }) else { return }

        // 1. Explicit Image-Based Lighting with a valid 360 studio ambient equirectangular map.
        // This provides natural PBR ambient reflections and silences the RealityKit warning:
        // "EnvironmentResource with no skybox texture is no longer supported. Please use ImageBasedLightResource instead."
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [238, 240, 246, 255]
        if let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage(),
           let envResource = try? EnvironmentResource(equirectangular: cgImage) {
            let iblEntity = Entity()
            iblEntity.name = "StudioIBL"
            iblEntity.components.set(ImageBasedLightComponent(source: .single(envResource), intensityExponent: 0.8))
            content.add(iblEntity)
        }

        // 2. High-Fidelity Studio Key & Fill Lights for crisp shadows and clear dollhouse visualization
        let keyLight = DirectionalLight()
        keyLight.name = "StudioKeyLight"
        keyLight.light.color = .white
        keyLight.light.intensity = 2400
        keyLight.position = [2.2, 4.2, 2.2]
        keyLight.look(at: [0, 0, 0], from: [2.2, 4.2, 2.2], relativeTo: nil)
        content.add(keyLight)

        let fillLight = DirectionalLight()
        fillLight.name = "StudioFillLight"
        fillLight.light.color = .init(white: 0.96, alpha: 1.0)
        fillLight.light.intensity = 1200
        fillLight.position = [-2.5, 3.2, -2.0]
        fillLight.look(at: [0, 0, 0], from: [-2.5, 3.2, -2.0], relativeTo: nil)
        content.add(fillLight)
    }

    // MARK: - Spatial Violation Overlay

    private static let overlayPrefix = "ViolationOverlay"

    /// Rebuilds the violation highlights when the marker set changes.
    /// Renders clean outlined perimeter shapes with soft translucent interior fill,
    /// color-coded by clearance rule so each violation is instantly distinguishable.
    private func syncViolationOverlay(on root: Entity) {
        let markers = viewModel.showViolations ? viewModel.violationMarkers : []
        let signature = "\(Self.overlayPrefix)-\(markers.map(\.id).hashValue)"

        if markers.isEmpty == false, root.children.contains(where: { $0.name == signature }) { return }
        for child in root.children where child.name.hasPrefix(Self.overlayPrefix) {
            child.removeFromParent()
        }
        guard !markers.isEmpty else { return }

        let overlay = Entity()
        overlay.name = signature
        for marker in markers {
            let baseColor: UIColor = marker.uiColor

            // 1. Soft interior fill material (very subtle, floor texture stays visible)
            var fillMaterial = UnlitMaterial(color: baseColor)
            fillMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.14))

            // 2. Crisp perimeter outline stroke material
            var strokeMaterial = UnlitMaterial(color: baseColor)
            strokeMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.92))

            if marker.isDoorSwing || marker.ruleId == PaneroZelnikRule.doorSwingUnobstructed {
                // -------------------------------------------------------------
                // Contextual Architectural Door Swing Shape (90° Radial Arc)
                // -------------------------------------------------------------
                let pivotX = marker.doorPivotX
                let pivotZ = marker.doorPivotZ
                let radius = marker.doorSwingRadius
                let startAngle = marker.doorStartAngle
                let sweepAngle = marker.doorSweepAngle
                let strokeThickness: Float = 0.022

                // 1. Straight Edge 1: Door Closed Position along Wall / Threshold
                let endX1 = pivotX + radius * cos(startAngle)
                let endZ1 = pivotZ + radius * sin(startAngle)
                let edge1 = ModelEntity(
                    mesh: .generateBox(size: [strokeThickness, 0.005, radius]),
                    materials: [strokeMaterial]
                )
                edge1.position = [(pivotX + endX1) / 2.0, 0.006, (pivotZ + endZ1) / 2.0]
                edge1.orientation = simd_quatf(angle: -startAngle + Float.pi / 2.0, axis: [0, 1, 0])
                overlay.addChild(edge1)

                // 2. Straight Edge 2: Door Leaf in Open Position (Swung 90° into room)
                let endAngle = startAngle + sweepAngle
                let endX2 = pivotX + radius * cos(endAngle)
                let endZ2 = pivotZ + radius * sin(endAngle)
                let edge2 = ModelEntity(
                    mesh: .generateBox(size: [strokeThickness * 1.5, 0.006, radius]),
                    materials: [strokeMaterial]
                )
                edge2.position = [(pivotX + endX2) / 2.0, 0.006, (pivotZ + endZ2) / 2.0]
                edge2.orientation = simd_quatf(angle: -endAngle + Float.pi / 2.0, axis: [0, 1, 0])
                overlay.addChild(edge2)

                // 3. Hinge Pivot Pin on the wall
                let hinge = ModelEntity(
                    mesh: .generateCylinder(height: 0.008, radius: 0.035),
                    materials: [strokeMaterial]
                )
                hinge.position = [pivotX, 0.006, pivotZ]
                overlay.addChild(hinge)

                // 4. Smooth 16-Segment Curved Arc representing door swing path
                let segments = 16
                let segLength = 2.0 * radius * sin(abs(sweepAngle) / (2.0 * Float(segments)))
                for k in 0..<segments {
                    let a1 = startAngle + (Float(k) / Float(segments)) * sweepAngle
                    let a2 = startAngle + (Float(k + 1) / Float(segments)) * sweepAngle
                    let mid = (a1 + a2) / 2.0
                    let arcSegment = ModelEntity(
                        mesh: .generateBox(size: [strokeThickness, 0.005, segLength * 1.05]),
                        materials: [strokeMaterial]
                    )
                    arcSegment.position = [pivotX + radius * cos(mid), 0.006, pivotZ + radius * sin(mid)]
                    arcSegment.orientation = simd_quatf(angle: -mid + Float.pi / 2.0, axis: [0, 1, 0])
                    overlay.addChild(arcSegment)
                }

                // 5. Soft Interior Fill: 8 sector wedges covering the 90° door sweep
                let wedgeCount = 8
                let wedgeWidth = (radius * abs(sweepAngle) / Float(wedgeCount)) * 1.08
                for k in 0..<wedgeCount {
                    let midAngle = startAngle + (Float(k) + 0.5) * (sweepAngle / Float(wedgeCount))
                    let wx = pivotX + (radius * 0.5) * cos(midAngle)
                    let wz = pivotZ + (radius * 0.5) * sin(midAngle)
                    let wedge = ModelEntity(
                        mesh: .generateBox(size: [wedgeWidth, 0.002, radius]),
                        materials: [fillMaterial]
                    )
                    wedge.position = [wx, 0.005, wz]
                    wedge.orientation = simd_quatf(angle: -midAngle + Float.pi / 2.0, axis: [0, 1, 0])
                    overlay.addChild(wedge)
                }
            } else {
                // Rectangular Outlined Shape with Soft Color Inside (Furniture Clearance Zone)
                let buffer = Float(marker.requiredCm / 100.0) * 0.35
                let extentX = marker.sizeX + buffer
                let extentZ = marker.sizeZ + buffer
                let strokeThickness: Float = 0.022

                // Soft rectangular interior fill
                let fillEntity = ModelEntity(
                    mesh: .generateBox(size: [extentX, 0.002, extentZ]),
                    materials: [fillMaterial]
                )
                fillEntity.position = [marker.centerX, 0.005, marker.centerZ]
                overlay.addChild(fillEntity)

                // 4 crisp perimeter outline border edges
                let north = ModelEntity(
                    mesh: .generateBox(size: [extentX, 0.005, strokeThickness]),
                    materials: [strokeMaterial]
                )
                north.position = [marker.centerX, 0.006, marker.centerZ - extentZ / 2.0]
                overlay.addChild(north)

                let south = ModelEntity(
                    mesh: .generateBox(size: [extentX, 0.005, strokeThickness]),
                    materials: [strokeMaterial]
                )
                south.position = [marker.centerX, 0.006, marker.centerZ + extentZ / 2.0]
                overlay.addChild(south)

                let west = ModelEntity(
                    mesh: .generateBox(size: [strokeThickness, 0.005, extentZ]),
                    materials: [strokeMaterial]
                )
                west.position = [marker.centerX - extentX / 2.0, 0.006, marker.centerZ]
                overlay.addChild(west)

                let east = ModelEntity(
                    mesh: .generateBox(size: [strokeThickness, 0.005, extentZ]),
                    materials: [strokeMaterial]
                )
                east.position = [marker.centerX + extentX / 2.0, 0.006, marker.centerZ]
                overlay.addChild(east)
            }

            // 3. Slender vertical beacon stem connecting the floor clearance area to the floating alert pin
            var stemMaterial = UnlitMaterial(color: baseColor)
            stemMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.38))
            let beaconStem = ModelEntity(
                mesh: .generateCylinder(height: 0.85, radius: 0.005),
                materials: [stemMaterial]
            )
            beaconStem.position = [marker.centerX, 0.425, marker.centerZ]
            overlay.addChild(beaconStem)

            // 4. Floating 3D Warning Beacon Sphere at eye level in the matching rule color
            let pinMaterial = UnlitMaterial(color: baseColor)
            let pinBeacon = ModelEntity(
                mesh: .generateSphere(radius: 0.06),
                materials: [pinMaterial]
            )
            pinBeacon.position = [marker.centerX, 0.85, marker.centerZ]
            overlay.addChild(pinBeacon)
        }
        root.addChild(overlay)
    }

    private func applyOrientation(to entity: Entity) {
        let pitchQuat = simd_quatf(angle: pitch, axis: [1, 0, 0])
        let yawQuat = simd_quatf(angle: yaw, axis: [0, 1, 0])
        entity.orientation = pitchQuat * yawQuat
    }

    // MARK: - 3D Furniture Motion & Animation

    /// Initial modeled vertex centers of each furniture piece in MockRoom.usdz.
    /// Because MockRoom.usdz meshes have world coordinates baked into their vertices,
    /// translating them in RealityKit requires offsetting relative to their initial mesh origin:
    /// Tr = T - R * P
    private static let initialModelPositions: [String: (x: Float, z: Float)] = [
        "Bed": (-1.30, -1.04),
        "Desk": (2.125, -1.20),
        "Chair": (1.41, -1.20),
        "Entry Stool": (1.41, -1.20),
        "Closet": (-2.16, 1.20),
        "Sofa": (1.20, 1.075),
        "TV": (1.20, -1.83)
    ]

    /// Synchronizes 3D furniture entities with the active layout, stably positioning models
    /// across the floor to their new optimized coordinates.
    private func syncFurniturePositions(on root: Entity, animated: Bool) {
        guard let layout = viewModel.currentLayout else { return }

        for item in layout.furnitures where !item.isArchived {
            guard let entity = findFurnitureEntity(for: item, in: root) else { continue }

            let origin = Self.initialModelPositions[entity.name] ?? (x: item.positionX, z: item.positionZ)
            let P = SIMD3<Float>(origin.x, 0, origin.z)
            let T = SIMD3<Float>(item.positionX, 0, item.positionZ)
            let targetRot = simd_quatf(angle: item.rotationYaw, axis: [0, 1, 0])
            let rotatedP = targetRot.act(P)
            let targetTranslation = T - rotatedP

            guard targetTranslation.x.isFinite && targetTranslation.y.isFinite && targetTranslation.z.isFinite else { continue }

            // Ensure entity scale is intact and never collapses to 0
            let targetScale: SIMD3<Float> = (entity.name == "Entry Stool") ? SIMD3<Float>(repeating: 0.82) : SIMD3<Float>(repeating: 1.0)
            entity.stopAllAnimations()
            entity.scale = targetScale
            entity.orientation = targetRot
            entity.position = targetTranslation
        }
    }

    /// Matches a furniture domain object to its corresponding 3D USDZ mesh inside the room.
    private func findFurnitureEntity(for furniture: Furniture, in root: Entity) -> Entity? {
        if let exact = root.findEntity(named: furniture.name) {
            return exact
        }

        let lowerName = furniture.name.lowercased()
        let lowerCat = furniture.category.lowercased()

        if lowerName.contains("stool") {
            if let stool = root.findEntity(named: "Entry Stool") {
                return stool
            }
            if let chair = root.findEntity(named: "Chair") {
                let stool = chair.clone(recursive: true)
                stool.name = "Entry Stool"
                stool.position = [0, 0, 0]
                stool.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
                stool.scale = SIMD3<Float>(repeating: 0.82)
                if let parent = chair.parent {
                    parent.addChild(stool)
                } else {
                    root.addChild(stool)
                }
                return stool
            }
        }

        if lowerName.contains("bed") || lowerCat == "bed" {
            return root.findEntity(named: "Bed")
        }
        if lowerName.contains("desk") || lowerCat == "desk" {
            return root.findEntity(named: "Desk")
        }
        if lowerName.contains("chair") || lowerCat == "chair" {
            return root.findEntity(named: "Chair")
        }
        if lowerName.contains("sofa") || lowerCat == "sofa" {
            return root.findEntity(named: "Sofa")
        }
        if lowerName.contains("wardrobe") || lowerName.contains("closet") || lowerCat == "closet" {
            return root.findEntity(named: "Closet")
        }
        if lowerName.contains("tv") || lowerCat == "television" {
            return root.findEntity(named: "TV")
        }

        return nil
    }
}
