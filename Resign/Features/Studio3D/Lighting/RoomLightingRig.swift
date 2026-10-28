import RealityKit
import UIKit
import simd

/// An aperture and its outward facade direction in the normalized room frame.
struct WindowOpening: Hashable, Sendable {
    var center: SIMD3<Float> = [2.55, 1.45, 0]
    var width: Float = 1.4
    var height: Float = 1.2
    var outwardNormal: SIMD3<Float> = [1, 0, 0]
}

/// All the numbers worth tweaking live here.
struct RoomLightingTuning {
    // Daylight
    /// Direct sun exposure calibrated at a 3-meter source distance, in lumens at full daylight.
    var sunBeamLumens: Float = 60_000
    /// Soft sky light spreading from the window into the room, in lumens at full skylight.
    var skyFillLumens: Float = 24_000
    /// Broad interior fill keeps daytime readable when direct sun is behind the facade.
    var skyBounceLumens: Float = 48_000
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
/// Layout fixtures are mapped to ceiling positions and preserve their saved output and color temperature.
@MainActor
final class RoomLightingRig {
    private struct FixtureEntities {
        let definition: RoomLightingFixture
        let spot: SpotLight
        let fill: PointLight
        let bulb: ModelEntity
    }

    let root = Entity()
    let tuning: RoomLightingTuning
    private(set) var ambientExponent: Float
    var fixtureCount: Int { fixtures.count }

    private let sunBeam = SpotLight()
    private let skyFill = SpotLight()
    private let skyBounce = PointLight()
    private var fixtures: [FixtureEntities] = []

    private var opening = WindowOpening()
    private var openings = [WindowOpening()]
    private var additionalDaylight: [(opening: WindowOpening, beam: SpotLight, sky: SpotLight)] = []
    private var bounceCenter: SIMD3<Float>?
    private var configuredFixtures: [RoomLightingFixture]?
    private var lastSettings: LightingSimulationSettings?
    private var isBuilt = false
    private var bulbsAreLit: Bool?

    init(tuning: RoomLightingTuning? = nil, fixtures: [RoomLightingFixture]? = nil) {
        let tuning = tuning ?? RoomLightingTuning()
        self.tuning = tuning
        self.ambientExponent = tuning.nightAmbientExponent
        self.configuredFixtures = fixtures
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
        buildFixtures()
    }

    /// Call after the room model is loaded. If the opening is not found, its default is retained.
    func configure(opening newOpening: WindowOpening?) {
        if let newOpening {
            configure(openings: [newOpening], roomCenter: newOpening.center - newOpening.outwardNormal * 2.3 + SIMD3<Float>(0, 0.9, 0))
        } else {
            buildIfNeeded()
            if let lastSettings { apply(lastSettings) }
        }
    }

    /// An empty array deliberately disables daylight for scans with no windows.
    func configure(openings: [WindowOpening], roomCenter: SIMD3<Float>) {
        buildIfNeeded()
        self.openings = openings
        bounceCenter = roomCenter
        for lights in additionalDaylight {
            lights.beam.removeFromParent()
            lights.sky.removeFromParent()
        }
        additionalDaylight = []
        if let first = openings.first {
            opening = first
            updateBeamCone()
        }
        for (index, aperture) in openings.dropFirst().enumerated() {
            let beam = SpotLight()
            beam.name = "SunBeam\(index + 1)"
            beam.light.attenuationRadius = tuning.beamDistance + 20
            beam.components[SpotLightComponent.Shadow.self] = tuning.sunBeamShadows ? SpotLightComponent.Shadow() : nil
            let sky = SpotLight()
            sky.name = "SkyFill\(index + 1)"
            sky.light.innerAngleInDegrees = 35
            sky.light.outerAngleInDegrees = 88
            sky.light.attenuationRadius = 14
            sky.components[SpotLightComponent.Shadow.self] = tuning.shadowsEnabled && tuning.skyFillShadows ? SpotLightComponent.Shadow() : nil
            updateBeamCone(beam, opening: aperture)
            root.addChild(beam)
            root.addChild(sky)
            additionalDaylight.append((aperture, beam, sky))
        }
        if let lastSettings { apply(lastSettings) }
    }

    func setFixtures(_ fixtures: [RoomLightingFixture]?) {
        guard configuredFixtures != fixtures else { return }
        configuredFixtures = fixtures
        if isBuilt { rebuildFixtures() }
        if let lastSettings { apply(lastSettings) }
    }

    private func updateBeamCone() {
        updateBeamCone(sunBeam, opening: opening)
    }

    private func updateBeamCone(_ sunBeam: SpotLight, opening: WindowOpening) {
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
        for fixture in fixtures {
            fixture.spot.removeFromParent()
            fixture.fill.removeFromParent()
            fixture.bulb.removeFromParent()
        }
        fixtures = []
        bulbsAreLit = nil
        buildFixtures()
    }

    private func buildFixtures() {
        let definitions = configuredFixtures ?? tuning.fixturePositions.enumerated().map { index, position in
            RoomLightingFixture(
                name: "Preview Light \(index + 1)",
                position: position,
                brightness: tuning.fixtureSpotLumens,
                colorTemperatureKelvin: 3_000
            )
        }

        for (index, definition) in definitions.enumerated() {
            let color = UIColor(kelvin: definition.colorTemperatureKelvin)
            let spot = SpotLight()
            spot.name = "FixtureSpot\(index)"
            spot.light.color = color
            spot.light.innerAngleInDegrees = 60
            spot.light.outerAngleInDegrees = 88      // keep below 90 degrees
            spot.light.attenuationRadius = 14
            spot.light.intensity = 0
            spot.components[SpotLightComponent.Shadow.self] = tuning.shadowsEnabled ? SpotLightComponent.Shadow() : nil
            spot.position = definition.position
            spot.orientation = .facing([0, -1, 0])
            root.addChild(spot)

            let fill = PointLight()
            fill.name = "FixtureFill\(index)"
            fill.light.color = color
            fill.light.attenuationRadius = 9
            fill.light.intensity = 0
            fill.position = definition.position
            root.addChild(fill)

            let bulb = ModelEntity(
                mesh: .generateSphere(radius: 0.09),
                materials: [UnlitMaterial(color: .darkGray)]
            )
            bulb.name = "FixtureBulb\(index)"
            bulb.position = definition.position
            bulb.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(bulb)

            fixtures.append(FixtureEntities(definition: definition, spot: spot, fill: fill, bulb: bulb))
        }
    }

    // MARK: - Per-frame update

    func apply(_ settings: LightingSimulationSettings) {
        buildIfNeeded()
        lastSettings = settings
        let state = settings.sun

        if openings.isEmpty {
            sunBeam.isEnabled = false
            sunBeam.light.intensity = 0
            skyFill.isEnabled = false
            skyFill.light.intensity = 0
        } else {
            applyDaylight(state, opening: opening, beam: sunBeam, sky: skyFill)
        }
        for lights in additionalDaylight {
            applyDaylight(state, opening: lights.opening, beam: lights.beam, sky: lights.sky)
        }

        let skyAmount: Float = openings.isEmpty ? 0 : state.skylight
        skyBounce.position = bounceCenter ?? (opening.center - opening.outwardNormal * 2.3 + SIMD3<Float>(0, 0.9, 0))
        skyBounce.light.color = UIColor(kelvin: 6500 + 1000 * Double(1 - state.skylight))
        skyBounce.light.intensity = tuning.skyBounceLumens * skyAmount
        skyBounce.isEnabled = skyAmount > 0.001

        // Ceiling fixtures
        let lightsOn = settings.artificialLightsOn
        for fixture in fixtures {
            let fixtureIsOn = lightsOn && fixture.definition.isOn
            let output = fixtureIsOn ? fixture.definition.brightness : 0
            fixture.spot.light.color = UIColor(kelvin: fixture.definition.colorTemperatureKelvin)
            fixture.spot.light.intensity = output
            fixture.spot.isEnabled = output > 0

            let fillRatio = tuning.fixtureFillLumens / max(1, tuning.fixtureSpotLumens)
            fixture.fill.light.color = fixture.spot.light.color
            fixture.fill.light.intensity = output * fillRatio
            fixture.fill.isEnabled = output > 0
        }
        if bulbsAreLit != lightsOn {
            bulbsAreLit = lightsOn
            for fixture in fixtures {
                let bulbIsOn = lightsOn && fixture.definition.isOn
                let color = bulbIsOn ? UIColor(kelvin: fixture.definition.colorTemperatureKelvin) : UIColor.darkGray
                fixture.bulb.model?.materials = [UnlitMaterial(color: color)]
            }
        }

        // Almost no environment light: without sun or lamps the room should be dark.
        let range = tuning.dayAmbientExponent - tuning.nightAmbientExponent
        ambientExponent = tuning.nightAmbientExponent + range * state.skylight
    }

    private func applyDaylight(_ state: SunState, opening: WindowOpening, beam: SpotLight, sky: SpotLight) {
        let normal = simd_normalize(opening.outwardNormal)
        let towardSun = -state.rayDirection
        beam.position = opening.center + towardSun * tuning.beamDistance
        beam.orientation = .facing(state.rayDirection)
        beam.light.color = UIColor(kelvin: state.kelvin)
        let incidence = max(0, simd_dot(towardSun, normal))
        let grazing = min(1, incidence / 0.15)
        let transmission = grazing * grazing * (3 - 2 * grazing)
        let direct = state.daylight * incidence * transmission
        let distanceScale = tuning.beamDistance / 3
        beam.light.intensity = tuning.sunBeamLumens * distanceScale * distanceScale * direct
        beam.isEnabled = direct > 0.001

        sky.position = opening.center - normal * 0.16
        sky.orientation = .facing(-normal)
        sky.light.color = UIColor(kelvin: 6500 + 1000 * Double(1 - state.skylight))
        sky.light.intensity = tuning.skyFillLumens * state.skylight
        sky.isEnabled = state.skylight > 0.001
    }

}
