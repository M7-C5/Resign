import SwiftUI
import RealityKit
import UIKit

struct RoomSimulationView: View {
    let settings: LightingSimulationSettings

    @State private var controller = RoomSceneController()
    @State private var dragOrigin: SIMD2<Float>?
    @State private var zoomOrigin: Float?

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
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
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
        view.environment.background = .color(UIColor(hex: "FAF9F6"))
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
