import SwiftUI
import RealityKit
import UIKit

struct RoomSimulationView: View {
    let settings: LightingSimulationSettings
    let fixtures: [RoomLightingFixture]?

    @State private var controller: RoomSceneController
    @State private var dragOrigin: SIMD2<Float>?
    @State private var zoomOrigin: Float?

    init(settings: LightingSimulationSettings, fixtures: [RoomLightingFixture]? = nil) {
        self.settings = settings
        self.fixtures = fixtures
        _controller = State(initialValue: RoomSceneController(fixtures: fixtures))
    }

    var body: some View {
        RoomRenderSurface(controller: controller, settings: settings)
            .overlay {
                if controller.loadState == .failed {
                    Text("Room preview unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragOrigin == nil {
                            dragOrigin = SIMD2(controller.yaw, controller.pitch)
                        }
                        guard let origin = dragOrigin else { return }
                        controller.setOrbit(
                            yaw: origin.x - Float(value.translation.width) * 0.008,
                            pitch: origin.y + Float(value.translation.height) * 0.008
                        )
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if zoomOrigin == nil { zoomOrigin = controller.distance }
                        controller.setDistance((zoomOrigin ?? 12) / Float(value.magnification))
                    }
                    .onEnded { _ in zoomOrigin = nil }
            )
            .accessibilityLabel("Room lighting preview")
            .accessibilityHint("Drag to rotate. Pinch to zoom.")
            .onChange(of: fixtures) { _, newFixtures in
                controller.setLightingFixtures(newFixtures)
            }
    }
}

/// Non-AR RealityKit surface. Lights are updated from `updateUIView` every time the settings change.
private struct RoomRenderSurface: UIViewRepresentable {
    let controller: RoomSceneController
    let settings: LightingSimulationSettings

    final class Coordinator {
        var loadTask: Task<Void, Never>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 250.0 / 255, green: 249.0 / 255, blue: 246.0 / 255, alpha: 1))
        view.renderOptions.insert([.disableMotionBlur, .disableDepthOfField])

        controller.install(in: view)
        controller.rig.apply(settings)
        view.environment.lighting.intensityExponent = controller.rig.ambientExponent

        context.coordinator.loadTask = Task { @MainActor in
            await controller.load()
        }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        controller.rig.apply(settings)
        view.environment.lighting.intensityExponent = controller.rig.ambientExponent
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        view.scene.anchors.removeAll()
    }
}

#Preview("Room — day") {
    RoomSimulationView(settings: LightingSimulationSettings())
}

#Preview("Room — night, lights on") {
    RoomSimulationView(settings: LightingSimulationSettings(artificialLightsOn: true, minuteOfDay: 0))
}
