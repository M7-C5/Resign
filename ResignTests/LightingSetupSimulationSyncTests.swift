import Foundation
import Testing
import SwiftData
import RealityKit
import UIKit
@testable import Resign

struct LightingSetupSimulationSyncTests {
    @Test @MainActor func savedEditsAndRemovalReachTheExistingSimulationRig() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let room = Room(length: 6, width: 4, height: 2.8)
        let layout = Layout(name: "Lighting sync")
        room.layouts.append(layout)
        container.mainContext.insert(room)
        let editor = LightingSetupViewModel()
        editor.loadFromLayout(layout)
        editor.tapPosition([0.25, 0.75])
        editor.updateBrightness(1800)
        editor.updateColorTemp(2700)
        try editor.saveToLayout(layout, context: container.mainContext)

        let controller = RoomSceneController()
        let settings = LightingSimulationSettings(artificialLightsOn: true, minuteOfDay: 0)
        func synchronize() -> [RoomLightingFixture] {
            let source = RoomSimulationLayout(layout: layout)
            let fixtures = layout.lights.sorted { $0.name < $1.name }.map { RoomLightingFixture(light: $0, layout: source) }
            controller.setLightingFixtures(fixtures)
            controller.apply(settings)
            return fixtures
        }
        let initialFixtures = synchronize()
        #expect(initialFixtures.first?.colorTemperatureKelvin == 2700)
        #expect(controller.rig.fixtureCount == 1)
        let spot = try #require(controller.rig.root.findEntity(named: "FixtureSpot0") as? SpotLight)
        #expect(abs(spot.position.x + 1) < 0.001)
        #expect(abs(spot.position.z - 1.5) < 0.001)
        #expect(spot.light.intensity == 1800 * controller.rig.tuning.fixtureExposureGain)
        let initialColor = spot.light.color

        editor.updateBrightness(600)
        editor.updateColorTemp(6500)
        editor.tapPosition([0.75, 0.25])
        try editor.saveToLayout(layout, context: container.mainContext)
        let updatedFixtures = synchronize()
        #expect(updatedFixtures.first?.colorTemperatureKelvin == 6500)
        #expect(controller.rig.fixtureCount == 2)
        let edited = try #require(controller.rig.root.findEntity(named: "FixtureSpot0") as? SpotLight)
        #expect(edited !== spot)
        #expect(edited.light.intensity == 600 * controller.rig.tuning.fixtureExposureGain)
        #expect(edited.light.color != initialColor)

        editor.deleteSelectedDraft()
        editor.selectedDraftID = editor.drafts.first?.id
        editor.deleteSelectedDraft()
        try editor.saveToLayout(layout, context: container.mainContext)
        _ = synchronize()
        #expect(controller.rig.fixtureCount == 0)
        #expect(controller.rig.root.findEntity(named: "FixtureSpot0") == nil)
        #expect(controller.rig.root.findEntity(named: "FixtureBulb0") == nil)
    }

    @Test @MainActor func emptySavedLayoutDoesNotUsePreviewFixtures() {
        let controller = RoomSceneController()
        controller.setLightingFixtures([])
        controller.apply(LightingSimulationSettings(artificialLightsOn: true))
        #expect(controller.rig.fixtureCount == 0)
    }
}
