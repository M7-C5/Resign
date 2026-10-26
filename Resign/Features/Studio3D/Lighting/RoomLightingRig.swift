import RealityKit
import UIKit
import simd

/// The glass opening that lets daylight in (east wall). Detected from the model when possible.
struct WindowOpening {
    var center: SIMD3<Float> = [2.55, 1.45, 0]
    var width: Float = 1.4
    var height: Float = 1.2
}

/// All the numbers worth tweaking live here.
struct RoomLightingTuning {
    // Daylight
    /// Direct sun exposure calibrated at a 3-meter source distance, in lumens at full daylight.
    var sunBeamLumens: Float = 60_000
    /// Soft sky light spreading from the window into the room, in lumens at full skylight.
    var skyFillLumens: Float = 24_000
    /// Approximate diffuse daylight bounce from the window; RealityKit has no real-time GI.
    var skyBounceLumens: Float = 5_000
    /// How far outside the window the sun beam starts (meters).
    var beamDistance: Float = 12
    /// Adds a margin beyond the aperture so the window geometry, not the cone edge, shapes the beam.
    var beamSpread: Float = 1.2
    /// Fraction of the outer cone used for a gradual intensity falloff at its edge.
    var beamEdgeFeather: Float = 0.32

    // Ceiling fixtures
    var fixtureSpotLumens: Float = 60_000
    /// Small omnidirectional fill so the whole room glows a little when lamps are on.
    var fixtureFillLumens: Float = 16_000

    /// Environment light as a power of two. Very low: the room must look dark without lamps or sun.
    var nightAmbientExponent: Float = -6.5
    var dayAmbientExponent: Float = -5.5

    /// Used when no lamps are found in the model (meters, room space).
    var fixturePositions: [SIMD3<Float>] = [[-1.3, 2.4, 0], [1.3, 2.4, 0]]

    /// Optional fixture and diffuse-sky shadows. Direct sun has its own aperture shadow policy.
    #if targetEnvironment(simulator)
    var shadowsEnabled = false
    #else
    var shadowsEnabled = true
    #endif
    /// Required on simulator and device: the solid wall and frame shape the window aperture.
    var sunBeamShadows = true
    var skyFillShadows = true
}

extension simd_quatf {
    /// Rotation that points an entity's forward axis (-Z, which is what lights and cameras emit along)
    /// toward `direction`. Safe for straight-down and straight-up directions, unlike `look(at:)`
    /// with a default up vector.
    static func facing(_ direction: SIMD3<Float>) -> simd_quatf {
        let forward = SIMD3<Float>(0, 0, -1)
        guard simd_length(direction) > 1e-6 else { return simd_quatf(angle: 0, axis: [0, 1, 0]) }
        let target = simd_normalize(direction)
        if simd_dot(forward, target) < -0.9999 {
            return simd_quatf(angle: .pi, axis: [0, 1, 0])
        }
        return simd_quatf(from: forward, to: target)
    }
}

/// Owns every light in the room.
///
/// Daylight comes only from the window:
/// - `sunBeam`: a narrow spot placed outside the window, aimed through it, so it only paints
///   the patch of floor and wall that the window would actually let the sun reach.
/// - `skyFill`: a wide soft spot sitting in the window plane, facing into the room.
/// - `skyBounce`: an unshadowed fill at the same opening, approximating diffuse bounce.
///
/// Ceiling fixtures are a downward spot plus a small point-light fill, and only emit when switched on.
@MainActor
final class RoomLightingRig {
    let root = Entity()
    let tuning: RoomLightingTuning
    private(set) var ambientExponent: Float

    private let sunBeam = SpotLight()
    private let skyFill = SpotLight()
    private let skyBounce = PointLight()
    private var fixtureSpots: [SpotLight] = []
    private var fixtureFills: [PointLight] = []
    private var bulbs: [ModelEntity] = []

    private var opening = WindowOpening()
    private var fixturePositions: [SIMD3<Float>]
    private var lastSettings: LightingSimulationSettings?
    private var isBuilt = false
    private var bulbsAreLit: Bool?

    init(tuning: RoomLightingTuning? = nil) {
        let tuning = tuning ?? RoomLightingTuning()
        self.tuning = tuning
        self.ambientExponent = tuning.nightAmbientExponent
        self.fixturePositions = tuning.fixturePositions
        root.name = "LightingRig"
    }

    // MARK: - Setup

    func buildIfNeeded() {
        guard !isBuilt else { return }
        isBuilt = true

        sunBeam.name = "SunBeam"
        sunBeam.light.intensity = 0
        sunBeam.light.attenuationRadius = tuning.beamDistance + 20
        sunBeam.components[SpotLightComponent.Shadow.self] =
            tuning.sunBeamShadows ? SpotLightComponent.Shadow() : nil
        root.addChild(sunBeam)

        skyFill.name = "SkyFill"
        skyFill.light.intensity = 0
        skyFill.light.innerAngleInDegrees = 35
        skyFill.light.outerAngleInDegrees = 88
        skyFill.light.attenuationRadius = 14
        skyFill.components[SpotLightComponent.Shadow.self] =
            tuning.shadowsEnabled && tuning.skyFillShadows ? SpotLightComponent.Shadow() : nil
        root.addChild(skyFill)

        skyBounce.name = "SkyBounce"
        skyBounce.light.intensity = 0
        skyBounce.light.attenuationRadius = 14
        root.addChild(skyBounce)

        updateBeamCone()
        buildFixtures(at: fixturePositions)
    }

    /// Call after the model is loaded with whatever was found in it. Both parameters are optional;
    /// anything not found keeps its default.
    func configure(opening newOpening: WindowOpening?, fixturePositions newPositions: [SIMD3<Float>]?) {
        buildIfNeeded()
        if let newOpening {
            opening = newOpening
            updateBeamCone()
        }
        if let newPositions, !newPositions.isEmpty {
            fixturePositions = newPositions
            rebuildFixtures()
        }
        if let lastSettings { apply(lastSettings) }
    }

    private func updateBeamCone() {
        let radius = 0.55 * (opening.width * opening.width + opening.height * opening.height).squareRoot()
        let fullDegrees = 2 * atan(radius / tuning.beamDistance) * 180 / .pi * tuning.beamSpread
        let outer = min(60, max(1, fullDegrees))
        sunBeam.light.outerAngleInDegrees = outer
        // A wide, gradual falloff keeps the spotlight edge from reading as a circular pool.
        // The window wall and mullion shape direct sun that reaches the room.
        let feather = min(0.8, max(0, tuning.beamEdgeFeather))
        sunBeam.light.innerAngleInDegrees = outer * (1 - feather)
    }

    private func rebuildFixtures() {
        for entity in fixtureSpots { entity.removeFromParent() }
        for entity in fixtureFills { entity.removeFromParent() }
        for entity in bulbs { entity.removeFromParent() }
        fixtureSpots = []
        fixtureFills = []
        bulbs = []
        bulbsAreLit = nil
        buildFixtures(at: fixturePositions)
    }

    private func buildFixtures(at positions: [SIMD3<Float>]) {
        let warm = UIColor(red: 1, green: 0.82, blue: 0.62, alpha: 1)

        for (index, position) in positions.enumerated() {
            let spot = SpotLight()
            spot.name = "FixtureSpot\(index)"
            spot.light.color = warm
            spot.light.innerAngleInDegrees = 60
            spot.light.outerAngleInDegrees = 88      // keep below 90 degrees
            spot.light.attenuationRadius = 14
            spot.light.intensity = 0
            spot.components[SpotLightComponent.Shadow.self] = tuning.shadowsEnabled ? SpotLightComponent.Shadow() : nil
            spot.position = position
            spot.orientation = .facing([0, -1, 0])
            root.addChild(spot)
            fixtureSpots.append(spot)

            let fill = PointLight()
            fill.name = "FixtureFill\(index)"
            fill.light.color = warm
            fill.light.attenuationRadius = 9
            fill.light.intensity = 0
            fill.position = position
            root.addChild(fill)
            fixtureFills.append(fill)

            let bulb = ModelEntity(
                mesh: .generateSphere(radius: 0.09),
                materials: [UnlitMaterial(color: .darkGray)]
            )
            bulb.name = "FixtureBulb\(index)"
            bulb.position = position
            bulb.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(bulb)
            bulbs.append(bulb)
        }
    }

    // MARK: - Per-frame update

    func apply(_ settings: LightingSimulationSettings) {
        buildIfNeeded()
        lastSettings = settings
        let state = settings.sun

        // Direct sun: starts outside the window and travels through its center.
        let towardSun = -state.rayDirection
        sunBeam.position = opening.center + towardSun * tuning.beamDistance
        sunBeam.orientation = .facing(state.rayDirection)
        sunBeam.light.color = UIColor(kelvin: state.kelvin)
        // East-wall outward normal is +X. Never put an afternoon sun inside the room.
        let incidence = max(0, towardSun.x)
        let grazing = min(1, incidence / 0.15)
        let transmission = grazing * grazing * (3 - 2 * grazing)
        let direct = state.daylight * incidence * transmission
        // Moving the source farther away reduces beam divergence but also dims it.
        // Preserve the exposure calibrated at 3 m with inverse-square compensation.
        let distanceScale = tuning.beamDistance / 3
        sunBeam.light.intensity = tuning.sunBeamLumens * distanceScale * distanceScale * direct
        sunBeam.isEnabled = direct > 0.001

        // Sky light: from the window plane, into the room (-X).
        skyFill.position = opening.center + SIMD3<Float>(-0.16, 0, 0)
        skyFill.orientation = .facing([-1, 0, 0])
        skyFill.light.color = UIColor(kelvin: 6500 + 1000 * Double(1 - state.skylight))
        skyFill.light.intensity = tuning.skyFillLumens * state.skylight
        skyFill.isEnabled = state.skylight > 0.001

        // Diffuse bounce keeps the unlit parts of the room readable without
        // restoring the automatic environment that masks time-of-day changes.
        // Keep the unshadowed diffuse approximation inside the room, away from the facade.
        skyBounce.position = opening.center + SIMD3<Float>(-0.8, 0, 0)
        skyBounce.light.color = skyFill.light.color
        skyBounce.light.intensity = tuning.skyBounceLumens * state.skylight
        skyBounce.isEnabled = state.skylight > 0.001

        // Ceiling fixtures
        let lightsOn = settings.artificialLightsOn
        for spot in fixtureSpots {
            spot.light.intensity = lightsOn ? tuning.fixtureSpotLumens : 0
            spot.isEnabled = lightsOn
        }
        for fill in fixtureFills {
            fill.light.intensity = lightsOn ? tuning.fixtureFillLumens : 0
            fill.isEnabled = lightsOn
        }
        if bulbsAreLit != lightsOn {
            bulbsAreLit = lightsOn
            let color = lightsOn ? UIColor(red: 1, green: 0.88, blue: 0.7, alpha: 1) : UIColor.darkGray
            for bulb in bulbs {
                bulb.model?.materials = [UnlitMaterial(color: color)]
            }
        }

        // Almost no environment light: without sun or lamps the room should be dark.
        let range = tuning.dayAmbientExponent - tuning.nightAmbientExponent
        ambientExponent = tuning.nightAmbientExponent + range * state.skylight
    }
}
