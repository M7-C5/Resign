import Testing
import Foundation
import RealityKit
@testable import Resign

@Suite("Layout-only room preview")
struct LayoutOnlyPreviewTests {
    @Test @MainActor func viewerStartsNeutralUntilSimulationButtonIsPressed() {
        let model = Studio3DViewModel()
        #expect(!model.isSimulationEnabled && !model.isLightingPresented)
        #expect(model.previewLighting.previewMode == .layoutOnly)
        model.toggleLightingSimulation()
        #expect(model.isSimulationEnabled && model.isLightingPresented)
        model.discardLightingEditing()
        #expect(model.isSimulationEnabled && !model.isLightingPresented)
        model.toggleLightingSimulation()
        #expect(!model.isSimulationEnabled)
    }

    @Test @MainActor func switchingOffHidesMarkersAndPreservesConfirmedLightChoices() {
        let model = Studio3DViewModel()
        model.toggleLightingSimulation()
        model.lightingDraft.artificialLightsOn = true
        model.lightingDraft.minuteOfDay = 480
        model.confirmLightingEditing()
        #expect(model.isSimulationEnabled && !model.isLightingPresented)
        model.toggleLightingSimulation()
        #expect(!model.isSimulationEnabled && !model.isLightingPresented)
        #expect(model.previewLighting.artificialLightsOn && model.previewLighting.minuteOfDay == 480)
        model.toggleLightingSimulation()
        #expect(model.isSimulationEnabled && model.lightingDraft.minuteOfDay == 480)
        model.lightingDraft.minuteOfDay = 1200
        model.toggleLightingSimulation()
        #expect(!model.isSimulationEnabled && !model.isLightingPresented)
        #expect(model.previewLighting.minuteOfDay == 480) // Turning off discards pending edits.
        model.toggleLightingSimulation()
        #expect(model.isSimulationEnabled && model.lightingDraft.artificialLightsOn)
    }

    @Test @MainActor func layoutOnlyHidesAllGeneratedLightsAndMarkersAtAnyTime() {
        let fixture = RoomLightingFixture(name: "Saved ceiling light", position: [0, 2.6, 0],
                                          brightness: 600, colorTemperatureKelvin: 4000)
        let rig = RoomLightingRig(fixtures: [fixture])
        rig.apply(LightingSimulationSettings(artificialLightsOn: true, minuteOfDay: 720))
        #expect(rig.root.isEnabled)
        rig.apply(LightingSimulationSettings(artificialLightsOn: true, minuteOfDay: 720, previewMode: .layoutOnly))
        #expect(!rig.root.isEnabled)
        let neutralExposure = rig.ambientExponent
        rig.apply(LightingSimulationSettings(artificialLightsOn: false, minuteOfDay: 0, previewMode: .layoutOnly))
        #expect(!rig.root.isEnabled && rig.ambientExponent == neutralExposure)
        #expect(rig.fixtureCount == 1) // Hide the rig without deleting configured fixtures.
        rig.apply(LightingSimulationSettings(artificialLightsOn: true, minuteOfDay: 0))
        #expect(rig.root.isEnabled)
        #expect(rig.root.findEntity(named: "FixtureBulb0")?.isEnabled == true)
    }

    @Test @MainActor func neutralEnvironmentRestoresSimulationWithoutResettingCamera() throws {
        let controller = RoomSceneController(fixtures: [])
        controller.setOrbit(yaw: 0.5, pitch: 0.8)
        controller.setDistance(10)
        let key = try #require(controller.root.findEntity(named: "ArchitecturalKeyLight"))
        let fill = try #require(controller.root.findEntity(named: "ArchitecturalFillLight"))
        controller.apply(LightingSimulationSettings(previewMode: .layoutOnly))
        #expect(controller.root.components[EnvironmentLightingConfigurationComponent.self]?.environmentLightingWeight == 1)
        #expect(!controller.root.components.has(ImageBasedLightReceiverComponent.self))
        #expect(!controller.root.components.has(ImageBasedLightComponent.self))
        #expect(key.isEnabled && fill.isEnabled)
        controller.apply(LightingSimulationSettings())
        #expect(controller.root.components[EnvironmentLightingConfigurationComponent.self]?.environmentLightingWeight == 0)
        #expect(controller.root.components.has(ImageBasedLightReceiverComponent.self))
        #expect(!key.isEnabled && !fill.isEnabled)
        #expect(controller.yaw == 0.5 && controller.pitch == 0.8 && controller.distance == 10)
    }

    @Test @MainActor func modeParticipatesInConfirmAndDiscardWithoutChangingLightChoices() {
        let model = Studio3DViewModel()
        model.beginLightingEditing()
        model.lightingDraft.artificialLightsOn = true
        model.lightingDraft.minuteOfDay = 480
        model.lightingDraft.previewMode = .layoutOnly
        model.confirmLightingEditing()
        #expect(model.previewLighting.previewMode == .layoutOnly)
        model.beginLightingEditing()
        model.lightingDraft.previewMode = .simulation
        model.discardLightingEditing()
        #expect(model.previewLighting.previewMode == .layoutOnly)
        #expect(model.previewLighting.artificialLightsOn && model.previewLighting.minuteOfDay == 480)
    }

    @Test @MainActor func layoutModeSurvivesAsyncLoadAndFixtureUpdates() async throws {
        let controller = RoomSceneController(fixtures: [])
        controller.apply(LightingSimulationSettings(previewMode: .layoutOnly))
        await controller.load()
        #expect(controller.loadState == .loaded)
        #expect(!controller.rig.root.isEnabled)
        controller.setLightingFixtures([RoomLightingFixture(name: "Added", position: [1, 2.6, 0],
                                                            brightness: 600, colorTemperatureKelvin: 4000)])
        #expect(!controller.rig.root.isEnabled && controller.rig.fixtureCount == 1)
        let marker = try #require(controller.root.findEntity(named: "FixtureBulb0"))
        controller.apply(LightingSimulationSettings(artificialLightsOn: true))
        #expect(controller.rig.root.isEnabled && marker.isEnabled)
    }
}
