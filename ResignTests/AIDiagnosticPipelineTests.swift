//
//  AIDiagnosticPipelineTests.swift
//  ResignTests
//
//  Created by Antigravity on 21/10/26.
//

import Testing
import Foundation
@testable import Resign

@Suite("AI Diagnostics & Layout Optimizer Pipeline Tests")
struct AIDiagnosticPipelineTests {

    @Test @MainActor func compactPromptBuilderEnforcesCentimetersAndNo3DCoordinates() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let desk = Furniture(
            name: "Work Desk",
            category: "desk",
            positionX: 1.5,
            positionY: 0.0,
            positionZ: -1.2,
            length: 1.2,
            width: 0.65,
            height: 0.75
        )
        let chair = Furniture(
            name: "Chair",
            category: "chair",
            positionX: 1.5,
            positionY: 0.0,
            positionZ: -0.8,
            length: 0.5,
            width: 0.5,
            height: 0.9
        )
        let window = RoomOpening(type: "window", posX: 2.5, posY: 1.4, posZ: 0.0, width: 1.6, height: 1.2)
        let door = RoomOpening(type: "door", posX: -1.5, posY: 0.0, posZ: 2.1, width: 0.9, height: 2.1)
        room.openings = [window, door]

        let layout = Layout(name: "Test Layout")
        layout.furnitures = [desk, chair]

        let violation = SpatialViolation(
            ruleId: "R3",
            ruleTitle: "Desk Rear Clearance",
            severity: .critical,
            measuredClearanceCm: 45.0,
            requiredClearanceCm: 76.2,
            itemIds: [desk.id, chair.id],
            message: "Desk pull-back space is restricted"
        )

        let prompt = RoomDiagnosticPromptBuilder.buildPrompt(
            room: room,
            layout: layout,
            violations: [violation],
            userPreference: "Maximize Productivity"
        )

        // Verify prompt is compact in centimeters
        #expect(prompt.contains("500 cm"), "Room width should be formatted as 500 cm")
        #expect(prompt.contains("420 cm"), "Room length should be formatted as 420 cm")
        #expect(prompt.contains("R3"), "Prompt must include Rule ID R3")
        #expect(prompt.contains("45 cm"), "Prompt must include measured clearance in cm")
        #expect(prompt.contains("Do NOT calculate 3D coordinates"), "Prompt must explicitly forbid LLM from calculating 3D collision geometry")
    }

    @Test func responseValidatorStripsHallucinatedFurnitureIDs() {
        let validDeskID = UUID()
        let validBedID = UUID()
        let hallucinatedID = UUID()

        let validSet: Set<UUID> = [validDeskID, validBedID]

        let rawResponse = AIDiagnosticResponse(
            insights: [
                AIDiagnosticInsight(
                    ruleId: "R1",
                    involvedFurnitureIds: [validDeskID, hallucinatedID],
                    explanation: "Bottleneck between desk and unplaced item",
                    suggestedFix: "Shift desk 20cm",
                    sentiment: "-"
                )
            ],
            solverSettings: SolverSettings(
                pinnedItemIds: [validBedID, hallucinatedID],
                mustHaveItemIds: [validDeskID, UUID()],
                goalWeights: GoalWeights(spacious: 1.5, balanced: -0.2, reachable: 0.8)
            )
        )

        let validated = AIDiagnosticValidator.validate(rawResponse, activeFurnitureIDs: validSet)

        // Hallucinated ID must be stripped from insights
        #expect(validated.insights[0].involvedFurnitureIds == [validDeskID])
        // Hallucinated ID must be stripped from pinned items
        #expect(validated.solverSettings.pinnedItemIds == [validBedID])
        // Hallucinated ID must be stripped from must-have items
        #expect(validated.solverSettings.mustHaveItemIds == [validDeskID])
        // Weights must be clamped [0.0, 1.0]
        #expect(validated.solverSettings.goalWeights.spacious == 1.0)
        #expect(validated.solverSettings.goalWeights.balanced == 0.0)
        #expect(validated.solverSettings.goalWeights.reachable == 0.8)
    }

    @Test @MainActor func layoutOptimizerGeneratesThreeDistinctVariantsPreservingPins() {
        let room = Room(length: 4.2, width: 5.0, height: 2.6)
        let layout = Layout(name: "Initial")

        let bed = Furniture(
            name: "Bed",
            category: "bed",
            positionX: -1.5,
            positionY: 0.0,
            positionZ: -1.0,
            length: 2.0,
            width: 1.6,
            height: 1.0
        )
        let desk = Furniture(
            name: "Desk",
            category: "desk",
            positionX: 1.5,
            positionY: 0.0,
            positionZ: -1.2,
            length: 1.2,
            width: 0.65,
            height: 0.75
        )
        layout.furnitures = [bed, desk]

        // Pin the bed: it must remain at -1.5, -1.0 across all variants!
        let solverSettings = SolverSettings(
            pinnedItemIds: [bed.id],
            mustHaveItemIds: [bed.id, desk.id],
            goalWeights: GoalWeights(spacious: 0.9, balanced: 0.5, reachable: 0.7)
        )

        let optimizer = LayoutOptimizerEngine()
        let variants = optimizer.generateLayouts(for: room, from: layout, settings: solverSettings)

        #expect(variants.count == 3, "Optimizer must generate exactly 3 variants")
        let variantNames = variants.map(\.name)
        #expect(variantNames.contains("Circadian Productivity"))
        #expect(variantNames.contains("Open Flow & Circulation"))
        #expect(variantNames.contains("Restful Sanctuary"))

        for variant in variants {
            let variantBed = variant.furnitures.first { $0.name == "Bed" }
            #expect(variantBed != nil)
            #expect(variantBed?.positionX == bed.positionX, "Pinned bed X must remain unchanged")
            #expect(variantBed?.positionZ == bed.positionZ, "Pinned bed Z must remain unchanged")
        }
    }

    @Test @MainActor func endToEndInsightsViewModelDiagnosticFlow() async {
        let room = RoomRepository.createStandardMockRoom()
        guard let baseLayout = room.layouts.first else {
            #expect(Bool(false), "Standard mock room should have a layout")
            return
        }

        let viewModel = InsightsViewModel()
        await viewModel.runDiagnosticPipeline(for: room, in: baseLayout, preference: "Circadian Flow")

        #expect(!viewModel.isAnalyzing)
        #expect(viewModel.diagnosticResponse != nil)
        #expect(viewModel.generatedLayouts.count == 3)
        #expect(viewModel.selectedLayout != nil)
    }

    @Test func foundationModelJSONSanitizerExtractsRawJSONFromMarkdownAndProse() {
        let markdownFenced = """
        Here is the requested layout analysis:
        ```json
        {
          "insights": [],
          "solverSettings": {
            "pinnedItemIds": [],
            "mustHaveItemIds": [],
            "goalWeights": { "spacious": 0.8, "balanced": 0.5, "reachable": 0.7 }
          }
        }
        ```
        Hope this helps!
        """
        let sanitized = FoundationModelAIDiagnosticService.sanitizeJSONResponse(markdownFenced)
        #expect(sanitized.hasPrefix("{"))
        #expect(sanitized.hasSuffix("}"))
        #expect(!sanitized.contains("```"))
        #expect(!sanitized.contains("Here is the requested"))

        let data = sanitized.data(using: .utf8)
        #expect(data != nil)
        let decoded = try? JSONDecoder().decode(AIDiagnosticResponse.self, from: data!)
        #expect(decoded != nil)
        #expect(decoded?.solverSettings.goalWeights.spacious == 0.8)
    }

    @Test @MainActor func foundationModelAIDiagnosticServiceExecutesSafelyWithFallback() async throws {
        let room = RoomRepository.createStandardMockRoom()
        guard let layout = room.layouts.first else {
            #expect(Bool(false), "Room must have at least one layout")
            return
        }

        let service = FoundationModelAIDiagnosticService()
        let response = try await service.diagnose(
            room: room,
            layout: layout,
            violations: [],
            userPreference: "Spacious Circulation"
        )

        // Verifies that whether on-device Foundation Model is active or fallback engages,
        // a valid, sanitized AIDiagnosticResponse is guaranteed
        #expect(!response.solverSettings.mustHaveItemIds.isEmpty)
        #expect(response.solverSettings.goalWeights.spacious >= 0.0)
        #expect(response.engineSource == .rulebookFallback || response.engineSource == .appleIntelligence)
    }

    @Test func foundationModelResilientDecoderHandlesMissingIDAndMalformedFields() {
        let jsonWithoutID = """
        {
          "insights": [
            {
              "ruleId": "R1",
              "involvedFurnitureIds": ["E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "invalid-uuid"],
              "explanation": "Clearance corridor restricted",
              "suggestedFix": "Shift desk outward",
              "sentiment": "-"
            }
          ],
          "solverSettings": {
            "pinnedItemIds": ["E621E1F8-C36C-495A-93FC-0C247A3E6E5F"],
            "mustHaveItemIds": []
          }
        }
        """
        guard let data = jsonWithoutID.data(using: .utf8) else {
            #expect(Bool(false), "Data must not be nil")
            return
        }

        let decoded = try? JSONDecoder().decode(AIDiagnosticResponse.self, from: data)
        #expect(decoded != nil)
        #expect(decoded?.insights.count == 1)
        #expect(decoded?.insights[0].involvedFurnitureIds.count == 1)
        #expect(decoded?.solverSettings.goalWeights.spacious == 0.5)
    }
}

