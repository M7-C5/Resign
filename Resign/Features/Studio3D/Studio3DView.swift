//
//  Studio3DView.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import SwiftUI
import RealityKit
import simd

public struct Studio3DView: View {
    @Bindable public var viewModel: Studio3DViewModel
    public var usdzURL: URL?

    // 45° Dollhouse Default Perspective
    // Pitch ~37 degrees looking down into room, Yaw ~ -32 degrees angled
    private static let defaultPitch: Float = 0.65
    private static let defaultYaw: Float = -0.55
    private static let defaultScale: Float = 0.38

    @State private var pitch: Float = Studio3DView.defaultPitch
    @State private var yaw: Float = Studio3DView.defaultYaw
    @State private var zoomScale: Float = Studio3DView.defaultScale

    @State private var dragStartPitch: Float = Studio3DView.defaultPitch
    @State private var dragStartYaw: Float = Studio3DView.defaultYaw

    @State private var loadError: String? = nil

    public init(viewModel: Studio3DViewModel = Studio3DViewModel(), usdzURL: URL? = nil) {
        self.viewModel = viewModel
        self.usdzURL = usdzURL ?? USDZRoomLoader.findBundledMockRoomURL()
    }

    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if let url = usdzURL {
                RealityView { content in
                    do {
                        let entity = try await Entity(contentsOf: url)
                        entity.name = "RoomRoot"
                        entity.position = [0, -0.45, -2.7]
                        entity.scale = simd_float3(repeating: zoomScale)
                        applyOrientation(to: entity)
                        content.add(entity)
                    } catch {
                        self.loadError = "RealityKit load error: \(error.localizedDescription)"
                    }
                } update: { content in
                    if let entity = content.entities.first(where: { $0.name == "RoomRoot" }) {
                        entity.scale = simd_float3(repeating: zoomScale)
                        applyOrientation(to: entity)
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

            // Top HUD Overlay
            VStack {
                topHUD
                Spacer()
                bottomPerspectiveBar
            }
        }
    }

    // MARK: - Subviews

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
                        pitch = Studio3DView.defaultPitch
                        yaw = Studio3DView.defaultYaw
                        zoomScale = Studio3DView.defaultScale
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
                        pitch = Studio3DView.defaultPitch
                        yaw = Studio3DView.defaultYaw
                        zoomScale = Studio3DView.defaultScale
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

    // MARK: - Helpers

    private func applyOrientation(to entity: Entity) {
        let pitchQuat = simd_quatf(angle: pitch, axis: [1, 0, 0])
        let yawQuat = simd_quatf(angle: yaw, axis: [0, 1, 0])
        entity.orientation = pitchQuat * yawQuat
    }
}
