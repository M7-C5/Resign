import SwiftUI
import RealityKit
import UIKit
import simd
import Combine

struct RoomSimulationView: View {
    let controller: RoomSceneController
    let settings: LightingSimulationSettings
    let fixtures: [RoomLightingFixture]?
    var selectedFurnitureID: UUID? = nil
    var archiveTargetCenter: CGPoint? = nil
    var onSelectFurniture: ((UUID?) -> Void)?
    var onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?
    var onProjectSelectedFurniture: ((CGPoint?) -> Void)? = nil
    var onArchiveHover: ((Bool) -> Void)?
    var onArchiveDrop: ((UUID) -> Void)?
    var onBoundsResolved: (((minX: Float, maxX: Float, minZ: Float, maxZ: Float)) -> Void)?
    var onWallSegmentsResolved: (([RoomPlanSnapshot.WallSegment]) -> Void)?
    var onReloadScannedRoom: (() -> Void)?
    var onWindowDirectionsResolved: (([Double]) -> Void)?

    var body: some View {
        ZStack {
            RoomRenderSurface(
                controller: controller,
                settings: settings,
                selectedFurnitureID: selectedFurnitureID,
                archiveTargetCenter: archiveTargetCenter,
                onSelectFurniture: onSelectFurniture,
                onMoveFurniture: onMoveFurniture,
                onProjectSelectedFurniture: onProjectSelectedFurniture,
                onArchiveHover: onArchiveHover,
                onArchiveDrop: onArchiveDrop,
                onBoundsResolved: onBoundsResolved,
                onWallSegmentsResolved: onWallSegmentsResolved
            )

            // Zero Mock Fallback: Dedicated Scanned Room Error State
            if controller.loadState == .failed {
                ZStack {
                    Color(uiColor: .systemBackground).opacity(0.92)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .imageScale(.large)
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
        .accessibilityLabel(settings.previewMode == .layoutOnly ? "Room layout preview" : "Room 3D viewport")
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
    var selectedFurnitureID: UUID?
    var archiveTargetCenter: CGPoint?
    var onSelectFurniture: ((UUID?) -> Void)?
    var onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?
    var onProjectSelectedFurniture: ((CGPoint?) -> Void)?
    var onArchiveHover: ((Bool) -> Void)?
    var onArchiveDrop: ((UUID) -> Void)?
    var onBoundsResolved: (((minX: Float, maxX: Float, minZ: Float, maxZ: Float)) -> Void)?
    var onWallSegmentsResolved: (([RoomPlanSnapshot.WallSegment]) -> Void)?

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: ARView?
        unowned var controller: RoomSceneController
        var selectedFurnitureID: UUID?
        var archiveTargetCenter: CGPoint?
        var onSelectFurniture: ((UUID?) -> Void)?
        var onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?
        var onProjectSelectedFurniture: ((CGPoint?) -> Void)?
        var onArchiveHover: ((Bool) -> Void)?
        var onArchiveDrop: ((UUID) -> Void)?
        var updateSubscription: (any Cancellable)?

        var loadTask: Task<Void, Never>?
        private var isHoveringArchive = false

        private enum DragMode {
            case none
            case translating(furnitureID: UUID, offset: SIMD2<Float>)
            case orbiting(startYaw: Float, startPitch: Float)
        }

        private var dragMode: DragMode = .none
        private var pinchStartDistance: Float = 12

        init(
            controller: RoomSceneController,
            selectedFurnitureID: UUID?,
            archiveTargetCenter: CGPoint?,
            onSelectFurniture: ((UUID?) -> Void)?,
            onMoveFurniture: ((UUID, SIMD2<Float>) -> Void)?,
            onProjectSelectedFurniture: ((CGPoint?) -> Void)?,
            onArchiveHover: ((Bool) -> Void)?,
            onArchiveDrop: ((UUID) -> Void)?
        ) {
            self.controller = controller
            self.selectedFurnitureID = selectedFurnitureID
            self.archiveTargetCenter = archiveTargetCenter
            self.onSelectFurniture = onSelectFurniture
            self.onMoveFurniture = onMoveFurniture
            self.onProjectSelectedFurniture = onProjectSelectedFurniture
            self.onArchiveHover = onArchiveHover
            self.onArchiveDrop = onArchiveDrop
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

            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.updateSelectedProjection()
            }
        }

        func updateSelectedProjection() {
            guard let arView = view,
                  let id = selectedFurnitureID,
                  let container = arView.scene.findEntity(named: "Furniture_\(id.uuidString)") else {
                onProjectSelectedFurniture?(nil)
                return
            }
            let bounds = container.visualBounds(relativeTo: nil)
            let yPos = bounds.max.y.isFinite ? bounds.max.y + 0.08 : container.position.y + 0.8
            let pos = container.position(relativeTo: nil)
            let topCenter = SIMD3<Float>(pos.x, yPos, pos.z)
            let projected = arView.project(topCenter)
            onProjectSelectedFurniture?(projected)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = view, gesture.state == .ended else { return }
            let point = gesture.location(in: arView)

            if let hitEntity = arView.entity(at: point) {
                var current: Entity? = hitEntity
                while let p = current, !p.name.hasPrefix("Furniture_") {
                    current = p.parent
                }
                if let container = current, container.name.hasPrefix("Furniture_") {
                    let uuidStr = String(container.name.dropFirst("Furniture_".count))
                    if let id = UUID(uuidString: uuidStr) {
                        selectedFurnitureID = id
                        onSelectFurniture?(id)
                        updateSelectedProjection()
                        return
                    }
                }
            }
            // Tapped on empty floor or background
            selectedFurnitureID = nil
            onSelectFurniture?(nil)
            onProjectSelectedFurniture?(nil)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let arView = view else { return }
            let point = gesture.location(in: arView)

            switch gesture.state {
            case .began:
                if let hitEntity = arView.entity(at: point) {
                    var current: Entity? = hitEntity
                    while let p = current, !p.name.hasPrefix("Furniture_") {
                        current = p.parent
                    }

                    // Only enter floor translation drag if this furniture is ALREADY selected (must press/tap first)
                    if let container = current, container.name.hasPrefix("Furniture_") {
                        let uuidStr = String(container.name.dropFirst("Furniture_".count))
                        if let id = UUID(uuidString: uuidStr), id == selectedFurnitureID {
                            if let floorPos = projectToFloor(from: point, in: arView) {
                                let fPos = container.position
                                let offset = SIMD2<Float>(fPos.x - floorPos.x, fPos.z - floorPos.z)
                                dragMode = .translating(furnitureID: id, offset: offset)
                            } else {
                                dragMode = .translating(furnitureID: id, offset: .zero)
                            }
                            updateSelectedProjection()
                            return
                        }
                    }
                }

                // Began outside furniture: Camera orbit mode
                dragMode = .orbiting(startYaw: controller.yaw, startPitch: controller.pitch)

            case .changed:
                switch dragMode {
                case .translating(let id, let offset):
                    if let floorPos = projectToFloor(from: point, in: arView) {
                        let target = SIMD2<Float>(floorPos.x + offset.x, floorPos.z + offset.y)
                        onMoveFurniture?(id, target)
                        updateSelectedProjection()
                    }
                    if let targetCenter = archiveTargetCenter {
                        let windowTouch = arView.convert(point, to: nil)
                        let touchOnIcon = Studio3DViewModel.isWithinArchiveTarget(point: windowTouch, targetCenter: targetCenter, radius: 56)

                        let furnitureNearIcon: Bool
                        if let container = arView.scene.findEntity(named: "Furniture_\(id.uuidString)"),
                           let screenPos = arView.project(container.position(relativeTo: nil)) {
                            let localTarget = arView.convert(targetCenter, from: nil)
                            furnitureNearIcon = Studio3DViewModel.isWithinArchiveTarget(point: screenPos, targetCenter: localTarget, radius: 64)
                        } else {
                            furnitureNearIcon = false
                        }

                        let isHovering = touchOnIcon || furnitureNearIcon
                        if isHovering != isHoveringArchive {
                            isHoveringArchive = isHovering
                            onArchiveHover?(isHovering)
                        }
                    }

                case .orbiting(let startYaw, let startPitch):
                    let translation = gesture.translation(in: arView)
                    controller.setOrbit(
                        yaw: startYaw - Float(translation.x) * 0.007,
                        pitch: startPitch + Float(translation.y) * 0.007
                    )
                    updateSelectedProjection()

                case .none:
                    break
                }

            case .ended:
                switch dragMode {
                case .translating(let id, _):
                    var droppedInArchive = isHoveringArchive
                    if !droppedInArchive, let targetCenter = archiveTargetCenter {
                        let windowTouch = arView.convert(point, to: nil)
                        if Studio3DViewModel.isWithinArchiveTarget(point: windowTouch, targetCenter: targetCenter, radius: 56) {
                            droppedInArchive = true
                        }
                    }
                    if droppedInArchive {
                        isHoveringArchive = false
                        onArchiveHover?(false)
                        onArchiveDrop?(id)
                    }
                default:
                    break
                }
                dragMode = .none
                if isHoveringArchive {
                    isHoveringArchive = false
                    onArchiveHover?(false)
                }

            case .cancelled:
                dragMode = .none
                if isHoveringArchive {
                    isHoveringArchive = false
                    onArchiveHover?(false)
                }

            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartDistance = controller.distance
            case .changed:
                let scale = Float(gesture.scale)
                if scale > 0.05 {
                    controller.setDistance(pinchStartDistance / scale)
                    updateSelectedProjection()
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
            selectedFurnitureID: selectedFurnitureID,
            archiveTargetCenter: archiveTargetCenter,
            onSelectFurniture: onSelectFurniture,
            onMoveFurniture: onMoveFurniture,
            onProjectSelectedFurniture: onProjectSelectedFurniture,
            onArchiveHover: onArchiveHover,
            onArchiveDrop: onArchiveDrop
        )
    }

    func makeUIView(context: Context) -> ARView {
        let view = RoomPreviewARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.onViewportChange = { [weak controller] size in controller?.setViewportSize(size) }
        view.environment.background = .color(StudioTheme.uiCanvasBackground)
        view.renderOptions.insert([.disableMotionBlur, .disableDepthOfField])

        controller.install(in: view)
        controller.apply(settings)
        view.environment.lighting.intensityExponent = controller.rig.ambientExponent

        context.coordinator.setupGestures(in: view)

        context.coordinator.loadTask = Task { @MainActor in
            await controller.load()
            if let bounds = controller.roomHorizontalBounds {
                onBoundsResolved?(bounds)
            }
            if !controller.roomWallSegments.isEmpty {
                onWallSegmentsResolved?(controller.roomWallSegments)
            }
        }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        controller.apply(settings)
        view.environment.lighting.intensityExponent = controller.rig.ambientExponent
        context.coordinator.selectedFurnitureID = selectedFurnitureID
        context.coordinator.archiveTargetCenter = archiveTargetCenter
        context.coordinator.onSelectFurniture = onSelectFurniture
        context.coordinator.onMoveFurniture = onMoveFurniture
        context.coordinator.onProjectSelectedFurniture = onProjectSelectedFurniture
        context.coordinator.onArchiveHover = onArchiveHover
        context.coordinator.onArchiveDrop = onArchiveDrop
        context.coordinator.updateSelectedProjection()
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        coordinator.updateSubscription?.cancel()
        (view as? RoomPreviewARView)?.onViewportChange = nil
        view.scene.anchors.removeAll()
    }
}

/// Resizes the existing interactive viewport without replacing its scene or gesture coordinator.
private final class RoomPreviewARView: ARView {
    var onViewportChange: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onViewportChange?(bounds.size)
    }
}

#Preview("Room — layout only") {
    RoomSimulationView(controller: RoomSceneController(),
                       settings: LightingSimulationSettings(previewMode: .layoutOnly), fixtures: nil)
}
