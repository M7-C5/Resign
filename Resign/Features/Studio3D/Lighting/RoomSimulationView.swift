import SwiftUI
import RealityKit
import UIKit
import simd

struct RoomSimulationView: View {
    let controller: RoomSceneController
    let settings: LightingSimulationSettings
    let fixtures: [RoomLightingFixture]?
    var onSelectFurniture: ((UUID?) -> Void)?
    var onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?
    var onRotateFurniture: ((UUID, Float) -> Void)?
    var onBoundsResolved: (((minX: Float, maxX: Float, minZ: Float, maxZ: Float)) -> Void)?
    var onReloadScannedRoom: (() -> Void)?
    var onWindowDirectionsResolved: (([Double]) -> Void)?

    var body: some View {
        ZStack {
            RoomRenderSurface(
                controller: controller,
                settings: settings,
                onSelectFurniture: onSelectFurniture,
                onMoveFurniture: onMoveFurniture,
                onRotateFurniture: onRotateFurniture,
                onBoundsResolved: onBoundsResolved
            )

            // Zero Mock Fallback: Dedicated Scanned Room Error State
            if controller.loadState == .failed {
                ZStack {
                    Color(uiColor: .systemBackground).opacity(0.92)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Unable to Load Scanned Room")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("The 3D room scan file could not be loaded. Please ensure the room was scanned and try again.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button {
                            onReloadScannedRoom?()
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
                .transition(.opacity)
            }
        }
        .accessibilityLabel("Room 3D viewport")
        .onChange(of: fixtures) { _, newFixtures in
            controller.setLightingFixtures(newFixtures)
        }
        .onChange(of: controller.resolvedWindowAzimuths) { _, directions in
            if let directions { onWindowDirectionsResolved?(directions) }
        }
    }
}

/// Non-AR RealityKit surface equipped with custom touch triage for furniture drag vs camera orbit.
private struct RoomRenderSurface: UIViewRepresentable {
    let controller: RoomSceneController
    let settings: LightingSimulationSettings
    var onSelectFurniture: ((UUID?) -> Void)?
    var onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?
    var onRotateFurniture: ((UUID, Float) -> Void)?
    var onBoundsResolved: (((minX: Float, maxX: Float, minZ: Float, maxZ: Float)) -> Void)?

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: ARView?
        unowned var controller: RoomSceneController
        var onSelectFurniture: ((UUID?) -> Void)?
        var onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?
        var onRotateFurniture: ((UUID, Float) -> Void)?

        var loadTask: Task<Void, Never>?

        private enum DragMode {
            case none
            case translating(furnitureID: UUID, offset: SIMD2<Float>)
            case rotating(furnitureID: UUID, initialTouchAngle: Float, initialYaw: Float, center: SIMD3<Float>)
            case orbiting(startYaw: Float, startPitch: Float)
        }

        private var dragMode: DragMode = .none
        private var selectedFurnitureID: UUID?
        private var pinchStartDistance: Float = 12
        private var twoFingerStartYaw: Float = 0

        init(
            controller: RoomSceneController,
            onSelectFurniture: ((UUID?) -> Void)?,
            onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?,
            onRotateFurniture: ((UUID, Float) -> Void)?
        ) {
            self.controller = controller
            self.onSelectFurniture = onSelectFurniture
            self.onMoveFurniture = onMoveFurniture
            self.onRotateFurniture = onRotateFurniture
        }

        func setupGestures(in arView: ARView) {
            self.view = arView

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            arView.addGestureRecognizer(tap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            arView.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            arView.addGestureRecognizer(pinch)

            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotation.delegate = self
            arView.addGestureRecognizer(rotation)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = view, gesture.state == .ended else { return }
            let point = gesture.location(in: arView)

            if let hitEntity = arView.entity(at: point) {
                var current: Entity? = hitEntity
                while let p = current, !p.name.hasPrefix("Furniture_") && !p.name.hasPrefix("FurnitureRotationHandle_") {
                    current = p.parent
                }
                if let handle = current, handle.name.hasPrefix("FurnitureRotationHandle_") {
                    let uuidStr = String(handle.name.dropFirst("FurnitureRotationHandle_".count))
                    if let id = UUID(uuidString: uuidStr) {
                        selectedFurnitureID = id
                        onSelectFurniture?(id)
                        return
                    }
                }
                if let container = current, container.name.hasPrefix("Furniture_") {
                    let uuidStr = String(container.name.dropFirst("Furniture_".count))
                    if let id = UUID(uuidString: uuidStr) {
                        selectedFurnitureID = id
                        onSelectFurniture?(id)
                        return
                    }
                }
            }
            // Tapped on empty floor or background
            selectedFurnitureID = nil
            onSelectFurniture?(nil)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let arView = view else { return }
            let point = gesture.location(in: arView)

            switch gesture.state {
            case .began:
                if let hitEntity = arView.entity(at: point) {
                    var current: Entity? = hitEntity
                    while let p = current, !p.name.hasPrefix("FurnitureRotationHandle_") && !p.name.hasPrefix("Furniture_") {
                        current = p.parent
                    }

                    // 1. Hit rotation handle: enter interactive rotation drag
                    if let handle = current, handle.name.hasPrefix("FurnitureRotationHandle_") {
                        let uuidStr = String(handle.name.dropFirst("FurnitureRotationHandle_".count))
                        if let id = UUID(uuidString: uuidStr),
                           let container = arView.scene.findEntity(named: "Furniture_\(uuidStr)") {
                            selectedFurnitureID = id
                            onSelectFurniture?(id)
                            if let floorPos = projectToFloor(from: point, in: arView) {
                                let center = container.position
                                let dx = floorPos.x - center.x
                                let dz = floorPos.z - center.z
                                let initialTouchAngle = atan2(dx, dz)
                                let initialYaw = container.orientation.angle * (container.orientation.axis.y >= 0 ? 1 : -1)
                                dragMode = .rotating(furnitureID: id, initialTouchAngle: initialTouchAngle, initialYaw: initialYaw, center: center)
                                return
                            }
                        }
                    }

                    // 2. Hit furniture body: enter floor translation drag
                    if let container = current, container.name.hasPrefix("Furniture_") {
                        let uuidStr = String(container.name.dropFirst("Furniture_".count))
                        if let id = UUID(uuidString: uuidStr) {
                            selectedFurnitureID = id
                            onSelectFurniture?(id)
                            if let floorPos = projectToFloor(from: point, in: arView) {
                                let fPos = container.position
                                let offset = SIMD2<Float>(fPos.x - floorPos.x, fPos.z - floorPos.z)
                                dragMode = .translating(furnitureID: id, offset: offset)
                            } else {
                                dragMode = .translating(furnitureID: id, offset: .zero)
                            }
                            return
                        }
                    }
                }

                // 3. Began outside furniture: Camera orbit mode
                dragMode = .orbiting(startYaw: controller.yaw, startPitch: controller.pitch)

            case .changed:
                switch dragMode {
                case .translating(let id, let offset):
                    if let floorPos = projectToFloor(from: point, in: arView) {
                        let target = SIMD2<Float>(floorPos.x + offset.x, floorPos.z + offset.y)
                        onMoveFurniture?(id, target)
                    }

                case .rotating(let id, let initialTouchAngle, let initialYaw, let center):
                    if let floorPos = projectToFloor(from: point, in: arView) {
                        let dx = floorPos.x - center.x
                        let dz = floorPos.z - center.z
                        let currentTouchAngle = atan2(dx, dz)
                        let delta = currentTouchAngle - initialTouchAngle
                        let targetYaw = initialYaw + delta
                        onRotateFurniture?(id, targetYaw)
                    }

                case .orbiting(let startYaw, let startPitch):
                    let translation = gesture.translation(in: arView)
                    controller.setOrbit(
                        yaw: startYaw - Float(translation.x) * 0.007,
                        pitch: startPitch + Float(translation.y) * 0.007
                    )

                case .none:
                    break
                }

            case .ended, .cancelled:
                dragMode = .none

            default:
                break
            }
        }

        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let arView = view, let id = selectedFurnitureID else { return }
            guard let container = arView.scene.findEntity(named: "Furniture_\(id.uuidString)") else { return }

            switch gesture.state {
            case .began:
                twoFingerStartYaw = container.orientation.angle * (container.orientation.axis.y >= 0 ? 1 : -1)

            case .changed:
                let delta = Float(gesture.rotation)
                let targetYaw = twoFingerStartYaw - delta
                onRotateFurniture?(id, targetYaw)

            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
               (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) {
                return true
            }
            return false
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartDistance = controller.distance
            case .changed:
                let scale = Float(gesture.scale)
                if scale > 0.05 {
                    controller.setDistance(pinchStartDistance / scale)
                }
            default:
                break
            }
        }

        /// Raycasts from screen point onto the authentic floor plane at `controller.floorLevel`.
        private func projectToFloor(from screenPoint: CGPoint, in arView: ARView) -> SIMD3<Float>? {
            guard let ray = arView.ray(through: screenPoint) else { return nil }
            guard abs(ray.direction.y) > 1e-4 else { return nil }

            let floorY = controller.floorLevel
            let t = (floorY - ray.origin.y) / ray.direction.y
            guard t > 0 else { return nil }

            return ray.origin + t * ray.direction
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            onSelectFurniture: onSelectFurniture,
            onMoveFurniture: onMoveFurniture,
            onRotateFurniture: onRotateFurniture
        )
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 250.0 / 255, green: 249.0 / 255, blue: 246.0 / 255, alpha: 1))
        view.renderOptions.insert([.disableMotionBlur, .disableDepthOfField])

        controller.install(in: view)
        controller.rig.apply(settings)
        view.environment.lighting.intensityExponent = controller.rig.ambientExponent

        context.coordinator.setupGestures(in: view)

        context.coordinator.loadTask = Task { @MainActor in
            await controller.load()
            if let bounds = controller.roomHorizontalBounds {
                onBoundsResolved?(bounds)
            }
        }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        controller.rig.apply(settings)
        view.environment.lighting.intensityExponent = controller.rig.ambientExponent
        context.coordinator.onSelectFurniture = onSelectFurniture
        context.coordinator.onMoveFurniture = onMoveFurniture
        context.coordinator.onRotateFurniture = onRotateFurniture
        if let bounds = controller.roomHorizontalBounds {
            onBoundsResolved?(bounds)
        }
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        view.scene.anchors.removeAll()
    }
}
