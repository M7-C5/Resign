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
    /// Narrow beam of direct sun entering through the window, in lumens at full daylight.
    var sunBeamLumens: Float = 100_000
    /// Soft sky light spreading from the window into the room, in lumens at full skylight.
    var skyFillLumens: Float = 40_000
    /// How far outside the window the sun beam starts (meters).
    var beamDistance: Float = 3
    /// 1.0 = beam cone exactly as wide as the window. Larger = softer, wider patch.
    var beamSpread: Float = 1.0

    // Ceiling fixtures
    var fixtureSpotLumens: Float = 60_000
    /// Small omnidirectional fill so the whole room glows a little when lamps are on.
    var fixtureFillLumens: Float = 16_000

    /// Environment light as a power of two. Very low: the room must look dark without lamps or sun.
    var nightAmbientExponent: Float = -6.5
    var dayAmbientExponent: Float = -5.5

    /// Used when no lamps are found in the model (meters, room space).
    var fixturePositions: [SIMD3<Float>] = [[-1.3, 2.4, 0], [1.3, 2.4, 0]]

    /// Dynamic shadows are what let the walls and window frame shape the daylight.
    /// If the simulator renders them badly, set this to false.
    var shadowsEnabled = true
    /// Shadows for the two daylight lights. Off by default: the wall around the window can swallow
    /// all of the light. Turn `sunBeamShadows` on later to get a sharp window-shaped patch.
    var sunBeamShadows = false
    var skyFillShadows = false
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
///
/// Ceiling fixtures are a downward spot plus a small point-light fill, and only emit when switched on.
@MainActor
final class RoomLightingRig {
    let root = Entity()
    let tuning: RoomLightingTuning
    private(set) var ambientExponent: Float

    private let sunBeam = SpotLight()
    private let skyFill = SpotLight()
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
        if tuning.shadowsEnabled && tuning.sunBeamShadows { sunBeam.shadow = SpotLightComponent.Shadow() }
        root.addChild(sunBeam)

        skyFill.name = "SkyFill"
        skyFill.light.intensity = 0
        skyFill.light.innerAngleInDegrees = 50
        skyFill.light.outerAngleInDegrees = 85
        skyFill.light.attenuationRadius = 14
        if tuning.shadowsEnabled && tuning.skyFillShadows { skyFill.shadow = SpotLightComponent.Shadow() }
        root.addChild(skyFill)

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
        let outer = min(60, max(6, fullDegrees))
        sunBeam.light.outerAngleInDegrees = outer
        sunBeam.light.innerAngleInDegrees = outer * 0.75
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
            if tuning.shadowsEnabled { spot.shadow = SpotLightComponent.Shadow() }
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
        sunBeam.light.intensity = tuning.sunBeamLumens * state.daylight
        sunBeam.isEnabled = state.daylight > 0.001

        // Sky light: from the window plane, into the room (-X).
        skyFill.position = opening.center + SIMD3<Float>(-0.05, 0, 0)
        skyFill.orientation = .facing([-1, 0, 0])
        skyFill.light.color = UIColor(kelvin: 3500 + 3000 * Double(state.skylight))
        skyFill.light.intensity = tuning.skyFillLumens * state.skylight
        skyFill.isEnabled = state.skylight > 0.001

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
