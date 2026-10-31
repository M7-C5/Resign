//
//  SpatialJourneyFlowTests.swift
//  ResignTests
//
//  Created by Antigravity on 26/10/26.
//

import Testing
import Foundation
@testable import Resign

@Suite("Spatial Journey User Flow Tests")
struct SpatialJourneyFlowTests {

    @Test @MainActor func fullThreeScreenJourneyProgression() async {
        let room = RoomRepository.createViolatingMockRoom()
        let layout = room.layouts.first!
        let viewModel = InsightsViewModel()
        viewModel.loadRoom(room, initialLayout: layout)

        // Step 1: Preference Page setup
        viewModel.toggleKeyword(.feelsCramped)
        viewModel.toggleKeyword(.hardToMove)
        viewModel.userPreference = "My desk feels too cramped, and I need more space to move around."

        #expect(viewModel.selectedKeywords.contains(.feelsCramped))
        #expect(viewModel.selectedKeywords.contains(.hardToMove))
        #expect(viewModel.preference.freeText.contains("desk feels too cramped"))

        // Step 2: Running pipeline transitions to "Your Layout" insights
        await viewModel.runDiagnosticPipeline(for: room, in: layout)

        #expect(!viewModel.detectedViolations.isEmpty, "Your Layout screen should detect real violations")
        #expect(!viewModel.generatedLayouts.isEmpty, "Pipeline should generate layout suggestion variants")

        // Step 3: Layout Suggestions Screen
        let variants = viewModel.generatedLayouts
        #expect(variants.count >= 2, "Should have multiple layout options to compare")

        let firstOption = variants[0]
        viewModel.selectLayout(firstOption)
        #expect(viewModel.selectedLayout?.id == firstOption.id)

        let firstInsights = viewModel.layoutInsights[firstOption.id] ?? []
        #expect(!firstInsights.isEmpty, "Selected option must display dynamic layout insight cards")

        // Switch to Option 2 in carousel
        let secondOption = variants[1]
        viewModel.selectLayout(secondOption)
        #expect(viewModel.selectedLayout?.id == secondOption.id)

        let secondInsights = viewModel.layoutInsights[secondOption.id] ?? []
        #expect(!secondInsights.isEmpty, "Second option must also have tailored insights")

        // Step 4: Apply layout updates activeLayout
        viewModel.activeLayout = secondOption
        #expect(viewModel.activeLayout?.id == secondOption.id)
    }

    @Test @MainActor func presetRoomSwitchingResetsAndLoads() {
        let viewModel = InsightsViewModel()

        // 1. Load violating room
        let violatingRoom = RoomRepository.createViolatingMockRoom()
        viewModel.loadRoom(violatingRoom)
        #expect(viewModel.currentRoom?.id == violatingRoom.id)
        #expect(viewModel.currentRoom?.layouts.first?.furnitures.count == violatingRoom.layouts.first?.furnitures.count)

        // 2. Load USDZ mock room
        if let usdzRoom = try? RoomRepository.loadMockRoomFromUSDZ() {
            viewModel.loadRoom(usdzRoom)
            #expect(viewModel.currentRoom?.id == usdzRoom.id)
            #expect(viewModel.currentRoom?.width == usdzRoom.width)
        }
    }

    @Test @MainActor func diagnosticHighlightSynchronization() async {
        let room = RoomRepository.createViolatingMockRoom()
        let layout = room.layouts.first!
        let viewModel = InsightsViewModel()
        let studioViewModel = Studio3DViewModel()
        viewModel.loadRoom(room, initialLayout: layout)

        await viewModel.runDiagnosticPipeline(for: room, in: layout)

        // Check if any AI diagnostic insight has involved furniture
        if let insight = viewModel.diagnosticResponse?.insights.first(where: { !$0.involvedFurnitureIds.isEmpty }) {
            viewModel.selectInsight(insight)
            studioViewModel.highlightFurniture(ids: viewModel.highlightedFurnitureIDs)

            #expect(!studioViewModel.highlightedFurnitureIDs.isEmpty)
            #expect(studioViewModel.highlightedFurnitureIDs == viewModel.highlightedFurnitureIDs)

            viewModel.clearHighlights()
            studioViewModel.clearHighlights()
            #expect(studioViewModel.highlightedFurnitureIDs.isEmpty)
        }
    }

    @Test @MainActor func studioLayoutTransitionsAndOptimalHighlights() {
        let room = RoomRepository.createViolatingMockRoom()
        let baseLayout = room.layouts.first!
        let optimizer = LayoutOptimizerEngine()
        let variants = optimizer.generateLayouts(for: room, from: baseLayout, settings: SolverSettings())
        #expect(!variants.isEmpty)

        let studioViewModel = Studio3DViewModel()
        let chosenVariant = variants.first!

        // Apply layout to studio
        studioViewModel.applyLayout(chosenVariant, animated: true)
        #expect(studioViewModel.currentLayout?.id == chosenVariant.id)
        #expect(studioViewModel.shouldAnimateLayoutChange == true)
        #expect(studioViewModel.activeLayoutVersion > 0)

        // Set recommendation highlights
        studioViewModel.setRecommendationHighlights(for: chosenVariant)
        #expect(!studioViewModel.violationMarkers.isEmpty)
        #expect(studioViewModel.violationMarkers.allSatisfy { $0.ruleId == "OPT" })
        #expect(studioViewModel.violationMarkers.count == chosenVariant.furnitures.count)
    }
}

