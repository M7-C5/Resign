//
//  ResignTests.swift
//  ResignTests
//
//  Created by Valentino Manuel Gunawan on 16/10/26.
//

import Testing
import ModelIO
import RealityKit
import Foundation
import SwiftData
@testable import Resign

@Suite("Resign Architecture Smoke Tests")
struct ResignTests {

    @Test func placeholder() {
        #expect(true)
    }

    @Test func mockRoomUSDZContainsAllRequiredElements() {
        guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
            #expect(Bool(false), "MockRoom.usdz not found in Bundle.main")
            return
        }
        let asset = MDLAsset(url: url)
        #expect(asset.count > 0, "MDLAsset should load objects from MockRoom.usdz")
        
        let requiredNames = ["Window", "Door", "Bed", "Desk", "Chair", "Sofa", "Closet", "TV"]
        var foundNames: [String] = []
        
        func inspect(object: MDLObject) {
            if requiredNames.contains(object.name) {
                foundNames.append(object.name)
            }
            for i in 0..<object.children.count {
                inspect(object: object.children[i])
            }
        }
        
        for i in 0..<asset.count {
            inspect(object: asset.object(at: i))
        }
        
        for target in requiredNames {
            #expect(foundNames.contains(target), "Expected '\(target)' in MockRoom.usdz")
        }
    }

    @Test @MainActor func roomHierarchyPersistence() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let room = Room(
            name: "Master Bedroom",
            longitude: -122.4194,
            latitude: 37.7749,
            compass: 85.0,
            length: 4.2,
            width: 5.0,
            height: 2.6
        )

        let window = RoomOpening(type: "window", posX: 2.5, posY: 1.45, posZ: 0.0, width: 1.6, height: 1.2)
        room.openings.append(window)

        let layout = Layout(name: "Circadian Optimal")
        
        let bed = Furniture(name: "Queen Bed", category: "bed", texture: "oak_fabric", positionX: -1.3, positionY: 0.5, positionZ: -1.0, rotationYaw: 0, length: 2.0, width: 1.6, height: 1.0)
        let desk = Furniture(name: "Work Desk", category: "desk", texture: "metal_wood", positionX: 2.1, positionY: 0.75, positionZ: -1.2, rotationYaw: .pi / 2, length: 1.2, width: 0.65, height: 0.75)
        layout.furnitures.append(bed)
        layout.furnitures.append(desk)

        let light = Light(name: "Center Fixture", coordinateX: 2.0, coordinateY: 2.0, elevationZ: 2.6, brightness: 1200, colorTemp: 4000, isOn: true)
        layout.lights.append(light)

        let insight = Insight(title: "Great Morning Light", type: "+", detail: "Desk receives natural illumination.")
        layout.insights.append(insight)

        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let descriptor = FetchDescriptor<Room>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        
        let savedRoom = fetched[0]
        #expect(savedRoom.name == "Master Bedroom")
        #expect(savedRoom.openings.count == 1)
        #expect(savedRoom.openings[0].type == "window")
        #expect(savedRoom.layouts.count == 1)
        
        let savedLayout = savedRoom.layouts[0]
        #expect(savedLayout.furnitures.count == 2)
        #expect(savedLayout.lights.count == 1)
        #expect(savedLayout.insights.count == 1)
        let furnitureCategories = Set(savedLayout.furnitures.map(\.category))
        #expect(furnitureCategories.contains("bed"))
        #expect(furnitureCategories.contains("desk"))
        #expect(savedRoom.createdAt <= Date())
        #expect(savedLayout.createdAt <= Date())
    }

    @Test @MainActor func modelDefaultInitializers() {
        let room = Room()
        #expect(room.name == "Room")
        #expect(room.length == 4.2)
        #expect(room.width == 5.0)

        let opening = RoomOpening()
        #expect(opening.type == "window")

        let layout = Layout()
        #expect(layout.name == "Layout")

        let furniture = Furniture()
        #expect(furniture.name == "Furniture")
        #expect(furniture.isArchived == false)

        let light = Light()
        #expect(light.isOn == true)
        #expect(light.brightness == 800.0)

        let insight = Insight()
        #expect(insight.type == "+")
    }

    @Test @MainActor func furnitureArchivedAndRotationProperties() {
        let chair = Furniture(
            name: "Office Chair",
            category: "chair",
            texture: "charcoal_mesh",
            positionX: 1.4,
            positionY: 0.45,
            positionZ: -1.2,
            rotationYaw: .pi / 4,
            isArchived: true
        )
        #expect(chair.isArchived == true)
        #expect(chair.category == "chair")
        #expect(chair.texture == "charcoal_mesh")
        #expect(chair.rotationYaw == .pi / 4)
    }
}

// MARK: - LightingSetup ViewModel Tests

@Suite("LightingSetup ViewModel Tests")
struct LightingSetupViewModelTests {

    // MARK: Grid interaction

    @Test @MainActor func tapCell_emptyCell_addsNewDraftAndSelectsIt() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 2, row: 3)

        #expect(vm.drafts.count == 1)
        #expect(vm.drafts[0].gridColumn == 2)
        #expect(vm.drafts[0].gridRow == 3)
        #expect(vm.selectedDraftID == vm.drafts[0].id)
    }

    @Test @MainActor func tapCell_existingCell_selectsWithoutCreatingDuplicate() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 1, row: 1)
        let firstID = vm.drafts[0].id
        vm.tapCell(col: 1, row: 1) // tap same cell again

        #expect(vm.drafts.count == 1, "Should not create a second draft on the same cell")
        #expect(vm.selectedDraftID == firstID)
    }

    @Test @MainActor func deselectLight_clearsSelectionWithoutRemovingDraft() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 0, row: 0)
        vm.deselectLight()

        #expect(vm.drafts.count == 1, "Draft should still exist after deselect")
        #expect(vm.selectedDraftID == nil)
    }

    @Test @MainActor func deleteSelectedDraft_removesDraftAndClearsSelection() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 0, row: 0)
        vm.deleteSelectedDraft()

        #expect(vm.drafts.isEmpty)
        #expect(vm.selectedDraftID == nil)
    }

    // MARK: Auto-naming

    @Test @MainActor func autoNaming_incrementsCorrectlyAsDraftsAreAdded() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 0, row: 0)
        vm.tapCell(col: 1, row: 0)
        vm.tapCell(col: 2, row: 0)

        #expect(vm.drafts[0].name == "Lighting 1")
        #expect(vm.drafts[1].name == "Lighting 2")
        #expect(vm.drafts[2].name == "Lighting 3")
    }

    // MARK: Property mutators

    @Test @MainActor func updateBrightness_mutatesSelectedDraft() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 1, row: 1)
        vm.updateBrightness(2500)

        #expect(vm.selectedDraft?.brightness == 2500)
    }

    @Test @MainActor func updateColorTemp_mutatesSelectedDraft() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 2, row: 2)
        vm.updateColorTemp(4000)

        #expect(vm.selectedDraft?.colorTemp == 4000)
    }

    // MARK: Persistence

    @Test @MainActor func saveToLayout_persistsAllDraftsAsLightRecords() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let layout = Layout(name: "Test Layout")
        context.insert(layout)
        try context.save()

        let vm = LightingSetupViewModel()
        vm.tapCell(col: 0, row: 0)
        vm.tapCell(col: 2, row: 2)
        vm.tapCell(col: 4, row: 4)
        vm.updateBrightness(1500)  // mutate selected (4,4)
        vm.updateColorTemp(3500)

        try vm.saveToLayout(layout, context: context)

        let descriptor = FetchDescriptor<Light>()
        let lights = try context.fetch(descriptor)
        #expect(lights.count == 3, "All three drafts should be persisted as Light records")

        let coords = Set(lights.map { "\(Int($0.coordinateX)),\(Int($0.coordinateY))" })
        #expect(coords.contains("0,0"))
        #expect(coords.contains("2,2"))
        #expect(coords.contains("4,4"))

        // Validate the mutated light at (4,4)
        let mutated = lights.first { Int($0.coordinateX) == 4 && Int($0.coordinateY) == 4 }
        #expect(mutated?.brightness == 1500)
        #expect(mutated?.colorTemp == 3500)
        #expect(mutated?.elevationZ == 2.6, "Elevation should default to 2.6m ceiling height")
    }

    @Test @MainActor func saveToLayout_emptyDrafts_persistsZeroLights() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let layout = Layout(name: "Empty Layout")
        context.insert(layout)
        try context.save()

        let vm = LightingSetupViewModel()
        try vm.saveToLayout(layout, context: context)

        let descriptor = FetchDescriptor<Light>()
        let lights = try context.fetch(descriptor)
        #expect(lights.isEmpty, "No lights should be inserted if drafts was empty")
    }

    // MARK: Edge cases

    @Test @MainActor func lightDraft_defaultInitialization_hasSensibleDefaults() {
        let draft = LightDraft(gridColumn: 2, gridRow: 2)
        #expect(draft.name == "Lighting")
        #expect(draft.brightness == 1080.0)
        #expect(draft.colorTemp == 5000)
        #expect(draft.isOn == true)
        #expect(draft.gridColumn == 2)
        #expect(draft.gridRow == 2)
    }

    @Test @MainActor func deleteSelectedDraft_whenNoneSelected_doesNothing() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 0, row: 0)
        vm.deselectLight()

        #expect(vm.drafts.count == 1)
        vm.deleteSelectedDraft()
        #expect(vm.drafts.count == 1, "Should not delete anything when no light is selected")
    }

    @Test @MainActor func updateProperties_whenNoneSelected_doesNothing() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 1, row: 1)
        vm.deselectLight()

        vm.updateBrightness(2800)
        vm.updateColorTemp(3000)

        #expect(vm.drafts[0].brightness == 1080.0, "Draft brightness should remain untouched")
        #expect(vm.drafts[0].colorTemp == 5000, "Draft colorTemp should remain untouched")
    }

    @Test @MainActor func tapCell_switchSelectionBetweenExistingLights() {
        let vm = LightingSetupViewModel()
        vm.tapCell(col: 0, row: 0)
        let firstID = vm.selectedDraftID

        vm.tapCell(col: 4, row: 4)
        let secondID = vm.selectedDraftID

        #expect(firstID != secondID)
        #expect(vm.selectedDraft?.id == secondID)

        // Tap back on first cell
        vm.tapCell(col: 0, row: 0)
        #expect(vm.selectedDraftID == firstID)
        #expect(vm.drafts.count == 2, "Should still have exactly 2 drafts")
    }
}

@Suite("Layout lighting simulation integration")
struct LayoutLightingSimulationIntegrationTests {
    @Test func savedLightMapsGridAndLightingPropertiesToRoomFixture() {
        let light = Light(
            name: "Desk Light",
            coordinateX: 4,
            coordinateY: 0,
            elevationZ: 2.4,
            brightness: 1_600,
            colorTemp: 4_100,
            isOn: false
        )

        let fixture = RoomLightingFixture(light: light)

        #expect(fixture.id == light.id)
        #expect(fixture.name == "Desk Light")
        #expect(fixture.position == SIMD3<Float>(1.3, 2.4, -1.3))
        #expect(fixture.brightness == 1_600)
        #expect(fixture.colorTemperatureKelvin == 4_100)
        #expect(!fixture.isOn)
    }

    @Test @MainActor func simulatorUsesOnlyConfiguredLayoutFixtures() throws {
        let active = RoomLightingFixture(
            name: "Ceiling 1",
            position: [0.65, 2.6, -0.65],
            brightness: 1_200,
            colorTemperatureKelvin: 3_500
        )
        let inactive = RoomLightingFixture(
            name: "Ceiling 2",
            position: [-0.65, 2.6, 0.65],
            brightness: 900,
            colorTemperatureKelvin: 5_000,
            isOn: false
        )
        let rig = RoomLightingRig(fixtures: [active, inactive])

        rig.apply(LightingSimulationSettings(artificialLightsOn: true))

        let activeSpot = try #require(rig.root.findEntity(named: "FixtureSpot0") as? SpotLight)
        let inactiveSpot = try #require(rig.root.findEntity(named: "FixtureSpot1") as? SpotLight)
        #expect(activeSpot.position == active.position)
        #expect(activeSpot.isEnabled && activeSpot.light.intensity == active.brightness)
        #expect(!inactiveSpot.isEnabled && inactiveSpot.light.intensity == 0)

        let emptyRig = RoomLightingRig(fixtures: [])
        emptyRig.apply(LightingSimulationSettings(artificialLightsOn: true))
        #expect(emptyRig.root.findEntity(named: "FixtureSpot0") == nil)
    }
}

@Suite("Lighting simulation modal")
struct LightingSimulationModalTests {
    @Test @MainActor func editsRemainDraftUntilConfirmed() {
        let model = Studio3DViewModel()
        model.beginLightingEditing()
        model.lightingDraft.artificialLightsOn = true
        model.lightingDraft.minuteOfDay = 1140
        #expect(model.lightingSettings == LightingSimulationSettings())
        model.confirmLightingEditing()
        #expect(!model.isLightingPresented)
        model.beginLightingEditing()
        #expect(model.lightingDraft.artificialLightsOn)
        #expect(model.lightingDraft.minuteOfDay == 1140)
    }

    @Test @MainActor func discardRestoresLastConfirmedChoices() {
        let model = Studio3DViewModel()
        model.beginLightingEditing()
        model.lightingDraft.minuteOfDay = 360
        model.lightingDraft.artificialLightsOn = true
        model.confirmLightingEditing()
        model.beginLightingEditing()
        model.lightingDraft.minuteOfDay = 1200
        model.lightingDraft.artificialLightsOn = false
        model.discardLightingEditing()
        model.beginLightingEditing()
        #expect(model.lightingDraft.minuteOfDay == 360)
        #expect(model.lightingDraft.artificialLightsOn)
    }

    @Test @MainActor func newViewerStartsAtNoonWithLightsOff() {
        let model = Studio3DViewModel()
        #expect(!model.lightingSettings.artificialLightsOn)
        #expect(model.lightingSettings.timeLabel == "12.00")
        #expect(!model.isLightingPresented)
    }

    @Test func timeLabelsCoverDayBoundaries() {
        #expect(LightingSimulationSettings(minuteOfDay: 0).timeLabel == "00.00")
        #expect(LightingSimulationSettings(minuteOfDay: 1439).timeLabel == "23.59")
    }
}

@Suite("Geographic daylight")
struct GeographicDaylightTests {
    @Test func sunCrossesFromEastToWest() {
        let morning = LightingSimulationSettings(minuteOfDay: 8 * 60).sun
        let afternoon = LightingSimulationSettings(minuteOfDay: 16 * 60).sun
        #expect(morning.rayDirection.x < 0)
        #expect(afternoon.rayDirection.x > 0)
        #expect(morning.daylight > 0)
        #expect(afternoon.daylight > 0)
        #expect(LightingSimulationSettings(minuteOfDay: 0).sun.daylight == 0)
    }

    @Test func orientationRotatesSunWithoutChangingElevation() {
        var settings = LightingSimulationSettings(minuteOfDay: 8 * 60)
        let original = settings.sun
        settings.solarContext.roomHeadingDegrees = 180
        let rotated = settings.sun
        #expect(abs(rotated.rayDirection.x + original.rayDirection.x) < 0.0001)
        #expect(abs(rotated.rayDirection.z + original.rayDirection.z) < 0.0001)
        #expect(abs(rotated.elevation - original.elevation) < 0.0001)
    }

    @Test func geographicReferenceAndSeason() throws {
        // Equator at Greenwich, near equinox: sun nearly overhead at local noon.
        let date = try #require(ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z"))
        let engine = SolarEphemerisEngine()
        let noon = engine.position(at: date, latitude: 0, longitude: 0)
        #expect(noon.elevation * 180 / .pi > 87)
        let midnight = engine.position(at: date.addingTimeInterval(12 * 3600), latitude: 0, longitude: 0)
        #expect(midnight.elevation < -1.5)
        let summer = try #require(ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z"))
        let winter = try #require(ISO8601DateFormatter().date(from: "2026-12-21T12:00:00Z"))
        #expect(engine.position(at: summer, latitude: 70, longitude: 0).elevation > 0)
        #expect(engine.position(at: winter, latitude: 70, longitude: 0).elevation < 0)
    }

    @Test func timeZoneResolvesCivilTimeAndLongitudeChangesSolarTime() throws {
        let local = SolarSimulationContext()
        var utc = local
        utc.timeZoneIdentifier = "GMT"
        #expect(local.date(minuteOfDay: 720) == utc.date(minuteOfDay: 300))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-03-20T08:00:00Z"))
        let engine = SolarEphemerisEngine()
        let greenwich = engine.position(at: date, latitude: 0, longitude: 0)
        let east = engine.position(at: date, latitude: 0, longitude: 60)
        #expect(east.elevation > greenwich.elevation + 0.8)
    }

    @Test @MainActor func eastWindowRejectsAfternoonSunButKeepsSkyLight() throws {
        var tuning = RoomLightingTuning()
        tuning.shadowsEnabled = true
        let rig = RoomLightingRig(tuning: tuning)
        rig.apply(LightingSimulationSettings(minuteOfDay: 8 * 60))
        let beam = try #require(rig.root.findEntity(named: "SunBeam") as? SpotLight)
        let sky = try #require(rig.root.findEntity(named: "SkyFill") as? SpotLight)
        let bounce = try #require(rig.root.findEntity(named: "SkyBounce") as? PointLight)
        #expect(beam.isEnabled && beam.light.intensity > 0)
        #expect(beam.shadow != nil)
        let noonSettings = LightingSimulationSettings(minuteOfDay: 12 * 60)
        rig.apply(noonSettings)
        #expect(!beam.isEnabled)
        #expect(noonSettings.sun.skylight > 0.8)
        #expect(sky.isEnabled && sky.light.intensity > 0)
        #expect(bounce.isEnabled && bounce.light.intensity > 40_000)
        rig.apply(LightingSimulationSettings(minuteOfDay: 16 * 60))
        #expect(!beam.isEnabled && beam.light.intensity == 0)
        #expect(sky.isEnabled && sky.light.intensity > 0)
        rig.apply(LightingSimulationSettings(minuteOfDay: 0))
        #expect(!beam.isEnabled && !sky.isEnabled)
        rig.apply(LightingSimulationSettings(artificialLightsOn: true, minuteOfDay: 0))
        let lamp = try #require(rig.root.findEntity(named: "FixtureSpot0") as? SpotLight)
        #expect(lamp.light.intensity > 0)
        #expect(!beam.isEnabled)
    }

    @Test @MainActor func previewUsesRuntimeCompatibleShadowDefaults() throws {
        let rig = RoomLightingRig()
        rig.apply(LightingSimulationSettings(minuteOfDay: 8 * 60))
        let beam = try #require(rig.root.findEntity(named: "SunBeam") as? SpotLight)
        let sky = try #require(rig.root.findEntity(named: "SkyFill") as? SpotLight)
        let lamp = try #require(rig.root.findEntity(named: "FixtureSpot0") as? SpotLight)
        let bounce = try #require(rig.root.findEntity(named: "SkyBounce") as? PointLight)
        #if targetEnvironment(simulator)
        #expect(!rig.tuning.shadowsEnabled)
        #expect(!sky.components.has(SpotLightComponent.Shadow.self))
        #expect(!lamp.components.has(SpotLightComponent.Shadow.self))
        #else
        #expect(rig.tuning.shadowsEnabled)
        #expect(beam.shadow != nil && sky.shadow != nil && lamp.shadow != nil)
        #endif
        #expect(beam.components.has(SpotLightComponent.Shadow.self))
        #expect(beam.light.innerAngleInDegrees < beam.light.outerAngleInDegrees)
        #expect(
            abs((beam.light.outerAngleInDegrees - beam.light.innerAngleInDegrees) / beam.light.outerAngleInDegrees - rig.tuning.beamEdgeFeather) < 0.001
        )
        #expect(beam.isEnabled && beam.light.intensity > 0)
        #expect(sky.isEnabled && sky.light.intensity > 0)
        #expect(bounce.isEnabled && bounce.light.intensity > 0)
        #expect(bounce.position.x < sky.position.x)
        #expect(bounce.position.y > sky.position.y)
        #expect(!lamp.isEnabled)

        rig.apply(LightingSimulationSettings(minuteOfDay: 16 * 60))
        #expect(!beam.isEnabled)
        #expect(sky.isEnabled && sky.light.intensity > 0)
        #expect(bounce.isEnabled && bounce.light.intensity > 0)
        rig.apply(LightingSimulationSettings(minuteOfDay: 0))
        #expect(!beam.isEnabled && !sky.isEnabled)
        #expect(!bounce.isEnabled && bounce.light.intensity == 0)
    }

    @Test @MainActor func studioUsesExplicitLightingInsteadOfDefaultEnvironment() throws {
        let controller = RoomSceneController()
        let lighting = try #require(controller.root.components[EnvironmentLightingConfigurationComponent.self])
        #expect(lighting.environmentLightingWeight == 0)
        let environment = try #require(controller.root.components[ImageBasedLightComponent.self])
        guard case .none = environment.source else {
            Issue.record("The studio must override the default image-based light")
            return
        }
        let receiver = try #require(controller.root.components[ImageBasedLightReceiverComponent.self])
        #expect(receiver.imageBasedLight === controller.root)
    }

    @Test @MainActor func windowAndFrameShapeDirectSunInTheLoadedRoom() async throws {
        let controller = RoomSceneController()
        controller.rig.apply(LightingSimulationSettings(minuteOfDay: 8 * 60))
        await controller.load()
        #expect(controller.loadState == .loaded)
        let beam = try #require(controller.rig.root.findEntity(named: "SunBeam") as? SpotLight)
        #expect(beam.components.has(SpotLightComponent.Shadow.self))
        for name in ["Wall_East_North", "Wall_East_South", "Wall_East_Top", "Wall_East_Bottom", "Frame_Mullion"] {
            let mesh = try #require(controller.root.findEntity(named: name))
            #expect(mesh.isEnabled)
            #expect(mesh.components[DynamicLightShadowComponent.self]?.castsShadow == true)
        }
        let glass = try #require(controller.root.findEntity(named: "Glass"))
        #expect(glass.components[DynamicLightShadowComponent.self]?.castsShadow == false)
    }

    @Test @MainActor func sourceConeCoversTheFullWindowDiagonal() throws {
        let rig = RoomLightingRig()
        let opening = WindowOpening(center: [2.55, 1.45, 0], width: 1.56, height: 1.16)
        rig.configure(opening: opening)
        let beam = try #require(rig.root.findEntity(named: "SunBeam") as? SpotLight)
        let halfAngle = beam.light.outerAngleInDegrees * .pi / 360
        let coverage = tan(halfAngle) * rig.tuning.beamDistance
        let cornerRadius = sqrt(opening.width * opening.width + opening.height * opening.height) / 2
        #expect(coverage > cornerRadius)
        #expect(beam.light.innerAngleInDegrees < beam.light.outerAngleInDegrees)
    }

    @Test @MainActor func movingSunFartherAwayPreservesWindowExposure() throws {
        var nearTuning = RoomLightingTuning()
        nearTuning.beamDistance = 3
        var farTuning = nearTuning
        farTuning.beamDistance = 12
        let near = RoomLightingRig(tuning: nearTuning)
        let far = RoomLightingRig(tuning: farTuning)
        let settings = LightingSimulationSettings(minuteOfDay: 8 * 60)
        near.apply(settings)
        far.apply(settings)
        let nearBeam = try #require(near.root.findEntity(named: "SunBeam") as? SpotLight)
        let farBeam = try #require(far.root.findEntity(named: "SunBeam") as? SpotLight)
        #expect(abs(farBeam.light.intensity / nearBeam.light.intensity - 16) < 0.001)
    }

    @Test @MainActor func previewCancelRestoresSunContext() {
        let model = Studio3DViewModel()
        let original = model.previewLighting
        model.beginLightingEditing()
        model.lightingDraft.solarContext.roomHeadingDegrees = 90
        model.lightingDraft.minuteOfDay = 480
        model.discardLightingEditing()
        #expect(model.previewLighting == original)
    }

    @Test @MainActor func placementUsesFixedOrthographicCamera() async throws {
        let scene = MockRoomRealityScene(topDown: true)
        try await scene.load()
        let camera = try #require(scene.camera.components[OrthographicCameraComponent.self])
        #expect(camera.scale == 4.2)
        #expect(scene.room?.findEntity(named: "Ceiling")?.isEnabled == false)
    }
}
