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

    @Test @MainActor func promptBuilderEnforcesStrictTokenBudgetUnder4096ContextLimit() {
        let room = Room(length: 5.0, width: 6.0, height: 2.8)
        room.openings = [
            RoomOpening(type: "window", posX: 2.0, posY: 1.4, posZ: 0.0, width: 1.5, height: 1.2),
            RoomOpening(type: "door", posX: -2.0, posY: 0.0, posZ: 2.5, width: 0.9, height: 2.1)
        ]

        let layout = Layout(name: "Crowded Test Layout")
        var items: [Furniture] = []
        for i in 1...10 {
            items.append(Furniture(
                name: "Furniture Item \(i)",
                category: i % 2 == 0 ? "desk" : "chair",
                positionX: Float(i) * 0.3 - 1.5,
                positionY: 0.0,
                positionZ: Float(i) * 0.2 - 1.0,
                length: 0.8,
                width: 0.6,
                height: 0.75
            ))
        }
        layout.furnitures = items

        // Generate 12 violations (mix of critical and warning)
        var violations: [SpatialViolation] = []
        for i in 1...12 {
            violations.append(SpatialViolation(
                ruleId: "R\(i % 6 + 1)",
                ruleTitle: "Clearance Bottleneck \(i)",
                severity: i % 2 == 0 ? .critical : .warning,
                measuredClearanceCm: Double(20 + i * 3),
                requiredClearanceCm: 76.2,
                itemIds: [items[0].id, items[1].id],
                message: "Extremely long diagnostic violation description that previously bloated prompt context tokens and exceeded model limits."
            ))
        }

        // Extremely long user free text that could risk prompt overflow
        let longFreeText = String(repeating: "I want an open, spacious workspace with maximum daylight. ", count: 20)
        let preference = RoomPreference(
            selectedKeywords: [.notEnoughSpace, .hardToMove],
            freeText: longFreeText
        )

        let prompt = RoomDiagnosticPromptBuilder.buildPrompt(
            room: room,
            layout: layout,
            violations: violations,
            userPreference: preference
        )

        // Verify that JSON is compact and not pretty-printed with wasteful indentation
        #expect(!prompt.contains("{\n  \"items\""), "JSON payload must be compact without pretty-printed indentation whitespace")

        // In iOS FoundationModels, 4096 context tokens corresponds to roughly 14,000-16,000 characters.
        // Prompt budget must strictly stay well below 7,500 characters (~1,800 tokens) even for complex crowded rooms.
        #expect(prompt.count < 7500)

        // Verify that measured violations in the compact payload are capped at top 6 critical violations
        let payload = RoomDiagnosticPromptBuilder.createPayload(
            room: room,
            layout: layout,
            violations: violations,
            userPreference: preference
        )
        #expect(payload.measuredViolations.count <= 6, "Payload must cap violations to top 6 critical bottlenecks")
        #expect(payload.userPreference.freeText.count <= 280, "User free text must be capped to 280 characters")
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

        // Verifies that whether Private Cloud Compute, on-device Foundation Model, or fallback engages,
        // a valid, sanitized AIDiagnosticResponse is guaranteed
        #expect(!response.solverSettings.mustHaveItemIds.isEmpty)
        #expect(response.solverSettings.goalWeights.spacious >= 0.0)
        #expect(response.engineSource == .rulebookFallback || response.engineSource == .appleIntelligence || response.engineSource == .privateCloudCompute)
    }

    @Test @MainActor func foundationModelComputeTargetDefaultsToPrivateCloudCompute() async throws {
        let defaultService = FoundationModelAIDiagnosticService()
        #expect(defaultService.computeTarget == .privateCloudCompute)

        let onDeviceService = FoundationModelAIDiagnosticService(computeTarget: .onDevice)
        #expect(onDeviceService.computeTarget == .onDevice)

        let autoService = FoundationModelAIDiagnosticService(computeTarget: .automatic)
        #expect(autoService.computeTarget == .automatic)
    }

    @Test func privateCloudComputeEngineSourceEncodesAndDecodesCleanly() throws {
        let response = AIDiagnosticResponse(
            insights: [],
            solverSettings: SolverSettings(),
            engineSource: .privateCloudCompute
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AIDiagnosticResponse.self, from: data)
        #expect(decoded.engineSource == .privateCloudCompute)
        #expect(decoded.engineSource.rawValue == "Private Cloud Compute")
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

