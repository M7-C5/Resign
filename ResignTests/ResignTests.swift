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

@Suite("Lighting simulation modal")
struct LightingSimulationModalTests {
    @Test @MainActor func editsRemainDraftUntilConfirmed() {
        let model = Studio3DViewModel()
        model.beginLightingEditing()
        model.lightingDraft.artificialLightsOn = false
        model.lightingDraft.minuteOfDay = 1140
        #expect(model.lightingSettings == LightingSimulationSettings())
        model.confirmLightingEditing()
        #expect(!model.isLightingPresented)
        model.beginLightingEditing()
        #expect(!model.lightingDraft.artificialLightsOn)
        #expect(model.lightingDraft.minuteOfDay == 1140)
    }

    @Test @MainActor func discardRestoresLastConfirmedChoices() {
        let model = Studio3DViewModel()
        model.beginLightingEditing()
        model.lightingDraft.minuteOfDay = 360
        model.confirmLightingEditing()
        model.beginLightingEditing()
        model.lightingDraft.minuteOfDay = 1200
        model.lightingDraft.artificialLightsOn = false
        model.discardLightingEditing()
        model.beginLightingEditing()
        #expect(model.lightingDraft.minuteOfDay == 360)
        #expect(model.lightingDraft.artificialLightsOn)
    }

    @Test @MainActor func newViewerStartsAtNoonWithLightsOn() {
        let model = Studio3DViewModel()
        #expect(model.lightingSettings.artificialLightsOn)
        #expect(model.lightingSettings.timeLabel == "12.00")
        #expect(!model.isLightingPresented)
    }

    @Test func timeLabelsCoverDayBoundaries() {
        #expect(LightingSimulationSettings(minuteOfDay: 0).timeLabel == "00.00")
        #expect(LightingSimulationSettings(minuteOfDay: 1439).timeLabel == "23.59")
    }
}

@Suite("Mock room lighting preview")
struct MockRoomLightingPreviewTests {
    @Test func daylightPeaksAtNoonAndFadesAtNight() {
        let noon = LightingSimulationSettings(minuteOfDay: 720)
        let midnight = LightingSimulationSettings(minuteOfDay: 0)
        #expect(abs(noon.daylightFactor - 1) < 0.0001)
        #expect(midnight.daylightFactor == 0)
        #expect(noon.ambientIntensity == midnight.ambientIntensity)
        #expect(LightingSimulationSettings(minuteOfDay: 360).daylightFactor == 0)
        #expect(LightingSimulationSettings(minuteOfDay: 1200).daylightFactor == 0)
    }

    @Test func artificialLightsAreIndependentOfTime() {
        let off = LightingSimulationSettings(artificialLightsOn: false, minuteOfDay: 720)
        let on = LightingSimulationSettings(artificialLightsOn: true, minuteOfDay: 0)
        #expect(off.artificialIntensity == 0)
        #expect(on.artificialIntensity > 0)
        #expect(off.daylightIntensity > on.daylightIntensity)
    }

    @Test @MainActor func previewRollsBackOnCancelAndPersistsOnConfirm() {
        let model = Studio3DViewModel()
        let original = model.previewLighting
        model.beginLightingEditing()
        model.lightingDraft.minuteOfDay = 0
        model.lightingDraft.artificialLightsOn = false
        #expect(model.previewLighting.artificialIntensity == 0)
        #expect(model.previewLighting.daylightFactor == 0)
        model.discardLightingEditing()
        #expect(model.previewLighting == original)
        model.beginLightingEditing()
        model.lightingDraft.minuteOfDay = 1200
        model.confirmLightingEditing()
        #expect(model.previewLighting.minuteOfDay == 1200)
    }
}

@Suite("Window daylight")
struct WindowDaylightTests {
    @Test func ambientDoesNotActAsUnrestrictedDaylight() {
        for minute in [0, 360, 720, 1080, 1439] {
            let settings = LightingSimulationSettings(minuteOfDay: minute)
            #expect(settings.ambientIntensity == 60)
        }
    }

    @Test @MainActor func realityKitWindowLightingAndDraftUpdates() async throws {
        let scene = MockRoomRealityScene(topDown: false)
        try await scene.load()
        let room = try #require(scene.room)
        let eastWall = try #require(room.findEntity(named: "Wall_East_North"))
        let glass = try #require(room.findEntity(named: "Glass"))
        #expect(eastWall.isEnabled)
        #expect(glass.components[DynamicLightShadowComponent.self]?.castsShadow == false)
        #expect(scene.daylight.shadow != nil)
        #expect(scene.daylight.position.x > 2.6)
        #expect(scene.daylight.light.outerAngleInDegrees == 24)
        scene.apply(LightingSimulationSettings(artificialLightsOn: false, minuteOfDay: 0))
        #expect(scene.daylight.light.intensity == 0)
        #expect(scene.fixtures.allSatisfy { $0.light.intensity == 0 })
        scene.apply(LightingSimulationSettings())
        #expect(scene.daylight.light.intensity > 0)
        #expect(scene.fixtures.count == 2)
        #expect(scene.fixtures.allSatisfy { $0.light.intensity > 0 })
        let original = scene.room
        try await scene.load()
        #expect(scene.room === original)
    }

    @Test @MainActor func placementUsesFixedOrthographicCamera() async throws {
        let scene = MockRoomRealityScene(topDown: true)
        try await scene.load()
        let camera = try #require(scene.camera.components[OrthographicCameraComponent.self])
        #expect(camera.scale == 4.2)
        #expect(scene.fixtures.isEmpty)
        #expect(scene.room?.findEntity(named: "Ceiling")?.isEnabled == false)
    }
}
