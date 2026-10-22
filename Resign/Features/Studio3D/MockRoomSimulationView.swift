import SwiftUI
import RealityKit
import Observation

struct MockRoomSimulationView: View {
    let settings: LightingSimulationSettings
    @State private var scene = MockRoomRealityScene(topDown: false)
    @State private var dragOrigin: SIMD2<Float>?
    @State private var zoomOrigin: Float?

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            do {
                try await scene.load()
                content.add(scene.root)
                scene.apply(settings)
            } catch {
                scene.loadFailed = true
            }
        } update: { _ in
            scene.apply(settings)
        }
        .overlay {
            if scene.loadFailed { Text("Room preview unavailable").foregroundStyle(.secondary) }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = SIMD2(scene.yaw, scene.pitch) }
                    guard let origin = dragOrigin else { return }
                    scene.yaw = origin.x - Float(value.translation.width) * 0.008
                    scene.pitch = min(1.35, max(0.15, origin.y + Float(value.translation.height) * 0.008))
                    scene.updateCamera()
                }
                .onEnded { _ in dragOrigin = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if zoomOrigin == nil { zoomOrigin = scene.distance }
                    scene.distance = min(20, max(5, (zoomOrigin ?? 12) / Float(value.magnification)))
                    scene.updateCamera()
                }
                .onEnded { _ in zoomOrigin = nil }
        )
        .accessibilityLabel("Mock room lighting preview")
        .accessibilityHint("Drag to rotate. Pinch to zoom.")
    }
}

private func colorFromTemperature(_ kelvin: Double) -> UIColor {
    let temp = max(1000.0, min(40000.0, kelvin)) / 100.0
    var red: Double = 0, green: Double = 0, blue: Double = 0
    if temp <= 66 {
        red = 255
        green = 99.4708025861 * log(temp) - 161.1195681661
        if temp <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(temp - 10) - 305.0447927307
        }
    } else {
        red = 329.698727446 * pow(temp - 60, -0.1332047592)
        green = 288.1221695283 * pow(temp - 60, -0.0755148492)
        blue = 255
    }
    let r = CGFloat(min(255, max(0, red))) / 255.0
    let g = CGFloat(min(255, max(0, green))) / 255.0
    let b = CGFloat(min(255, max(0, blue))) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: 1)
}

/// Shared RealityKit scene loader for the studio and the fixed lighting-placement view.
@MainActor
@Observable
final class MockRoomRealityScene {
    let root = Entity()
    let camera = Entity()
    let daylight = SpotLight()
    private(set) var fixtures: [SpotLight] = []
    private var bulbs: [ModelEntity] = []
    private var sunBeam: ModelEntity?
    let topDown: Bool
    var loadFailed = false
    var yaw: Float = -0.73
    var pitch: Float = 0.55
    var distance: Float = 12
    private(set) var room: Entity?

    init(topDown: Bool) {
        self.topDown = topDown
    }

    func load() async throws {
        guard room == nil else { return }
        guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let loaded = try await Entity(contentsOf: url)
        try Task.checkCancellation()
        configure(loaded)
        root.addChild(loaded)
        room = loaded

        if topDown {
            var orthographic = OrthographicCameraComponent()
            orthographic.scale = 4.2
            orthographic.scaleDirection = .vertical
            orthographic.near = 0.1
            orthographic.far = 30
            camera.components.set(orthographic)
            camera.look(at: .zero, from: [0, 10, 0], upVector: [0, 0, -1], relativeTo: nil)
        } else {
            var perspective = PerspectiveCameraComponent()
            perspective.fieldOfViewInDegrees = 40
            camera.components.set(perspective)
            updateCamera()
            configureLighting()
        }
        root.addChild(camera)
    }

    private func configure(_ entity: Entity) {
        let name = entity.name
        if name == "Ceiling" || (!topDown && (name == "Wall_West" || name.hasPrefix("Wall_South") || name == "Door")) {
            entity.isEnabled = false
        }
        entity.components.set(DynamicLightShadowComponent(castsShadow: name != "Glass"))
        entity.components.set(EnvironmentLightingConfigurationComponent(environmentLightingWeight: topDown ? 1 : 0.06))

        if var model = entity.components[ModelComponent.self] {
            if topDown {
                // Keep placement colors independent of simulated lighting.
                model.materials = model.materials.map { material in
                    if let pbr = material as? PhysicallyBasedMaterial {
                        var unlit = UnlitMaterial()
                        unlit.color = .init(tint: pbr.baseColor.tint, texture: pbr.baseColor.texture)
                        return unlit
                    }
                    return material
                }
            }
            entity.components.set(model)
        }
        for child in entity.children { configure(child) }
    }

    private func configureLighting() {
        // Natural light only from the east window (window-gated daylight)
        daylight.name = "WindowDaylight"
        daylight.light.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        // Narrower, more directional cone to simulate sun rays through window
        daylight.light.innerAngleInDegrees = 14
        daylight.light.outerAngleInDegrees = 20
        daylight.light.attenuationRadius = 18
        daylight.shadow = SpotLightComponent.Shadow()
        // Start position - will be updated by apply() based on time of day
        daylight.look(at: [-0.2, 0, 0], from: [5.8, 3.4, 0], relativeTo: nil)
        root.addChild(daylight)
        
        // Add visible sun beam/god rays
        let beamMesh = MeshResource.generateBox(size: [0.8, 0.02, 4.0])
        var beamMaterial = UnlitMaterial()
        beamMaterial.color = .init(tint: UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 0.15))
        beamMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.15))
        let beam = ModelEntity(mesh: beamMesh, materials: [beamMaterial])
        beam.name = "SunBeam"
        beam.position = [4.5, 1.8, 0]
        beam.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        beam.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(beam)
        sunBeam = beam

        for x: Float in [-1.3, 1.3] {
            let light = SpotLight()
            light.light.color = UIColor(red: 1, green: 0.82, blue: 0.6, alpha: 1)
            light.light.innerAngleInDegrees = 60
            light.light.outerAngleInDegrees = 95
            light.light.attenuationRadius = 7
            light.shadow = SpotLightComponent.Shadow()
            light.look(at: [x, 0, 0], from: [x, 2.45, 0], relativeTo: nil)
            root.addChild(light)
            fixtures.append(light)

            let bulb = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [UnlitMaterial(color: .gray)])
            bulb.position = [x, 2.45, 0]
            bulb.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(bulb)
            bulbs.append(bulb)
        }
    }

    func updateCamera() {
        let target: SIMD3<Float> = [0, 0.7, 0]
        let offset = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
        camera.look(at: target, from: target + offset, relativeTo: nil)
    }

    func apply(_ settings: LightingSimulationSettings) {
        guard !topDown else { return }
        let hour = settings.hourOfDay
        // Update daylight color temperature based on time
        let beamColor = colorFromTemperature(settings.colorTemperatureKelvin)
        daylight.light.color = beamColor
        
        // Calculate sun position - comes from east window, moves based on time
        if hour >= 6.0 && hour <= 18.0 {
            let t = (hour - 6.0) / 12.0 // 0 at sunrise, 1 at sunset
            // Sun moves higher in sky as it approaches noon
            let altitude = sin(t * .pi) // 0 at edges, 1 at noon
            // East window is at +X side; sun comes from outside east
            let sunDistance: Float = 6.2
            let sunHeight: Float = Float(2.6 + altitude * 1.4) // lower at sunrise/sunset, higher at noon
            let lateralOffset: Float = Float(sin(t * .pi) * 0.6 - 0.4)
            let lookTargetX: Float = Float(-0.4 + lateralOffset * 0.2)
            let lookTargetY: Float = Float(0.2 + altitude * 0.3)
            daylight.look(at: [lookTargetX, lookTargetY, 0], from: [sunDistance, sunHeight, lateralOffset], relativeTo: nil)
            // More intense for visible god rays
            daylight.light.intensity = Float(settings.daylightIntensity) * 16.0 * Float(pow(altitude, 0.6))
            
            // Update visible sun beam
            if let beam = sunBeam {
                beam.isEnabled = true
                beam.position = [Float(4.2 - altitude * 0.5), Float(1.6 + altitude * 0.8), lateralOffset]
                beam.orientation = simd_quatf(angle: Float(.pi / 2 - altitude * 0.3), axis: [0, 1, 0])
                var mat = UnlitMaterial()
                mat.color = .init(tint: beamColor.withAlphaComponent(CGFloat(0.08 + altitude * 0.12)))
                mat.blending = .transparent(opacity: .init(floatLiteral: Float(0.08 + altitude * 0.12)))
                beam.model?.materials = [mat]
                beam.scale = [Float(0.6 + altitude * 0.4), 0.02, Float(3.5 + altitude * 1.5)]
            }
        } else {
            // Night - no natural light from sun
            daylight.light.intensity = 0
            if let beam = sunBeam {
                beam.isEnabled = false
            }
        }
        
        for light in fixtures { light.light.intensity = Float(settings.artificialIntensity) * 3.5 }
        for bulb in bulbs {
            bulb.model?.materials = [UnlitMaterial(color: settings.artificialLightsOn
                ? UIColor(red: 1, green: 0.88, blue: 0.7, alpha: 1) : .darkGray)]
        }
    }
}

#Preview("Mock room — daylight") {
    MockRoomSimulationView(settings: LightingSimulationSettings())
}

#Preview("Mock room — night lights") {
    MockRoomSimulationView(settings: LightingSimulationSettings(minuteOfDay: 0))
}
