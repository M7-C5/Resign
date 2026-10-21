//
//  InsightsViewModel.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation
import Observation

@MainActor
@Observable
public final class InsightsViewModel {
    public var currentRoom: Room?
    public var activeLayout: Layout?
    public var detectedViolations: [SpatialViolation] = []
    public var diagnosticResponse: AIDiagnosticResponse?
    public var generatedLayouts: [Layout] = []
    public var selectedLayout: Layout?
    public var highlightedFurnitureIDs: Set<UUID> = []
    public var isAnalyzing: Bool = false
    public var errorMessage: String? = nil
    public var userPreference: String = "Balanced Productivity & Rest"

    private let clearanceEngine: SpatialClearanceEngine
    private let diagnosticService: AIDiagnosticServiceProtocol
    private let layoutOptimizer: LayoutOptimizerEngine

    public init() {
        self.clearanceEngine = SpatialClearanceEngine()
        self.diagnosticService = RulebookAIDiagnosticService()
        self.layoutOptimizer = LayoutOptimizerEngine()
    }

    public init(
        clearanceEngine: SpatialClearanceEngine,
        diagnosticService: AIDiagnosticServiceProtocol,
        layoutOptimizer: LayoutOptimizerEngine
    ) {
        self.clearanceEngine = clearanceEngine
        self.diagnosticService = diagnosticService
        self.layoutOptimizer = layoutOptimizer
    }

    public func loadRoom(_ room: Room, initialLayout: Layout? = nil) {
        self.currentRoom = room
        self.activeLayout = initialLayout ?? room.layouts.first
    }

    @MainActor
    public func runDiagnosticPipeline(
        for room: Room,
        in layout: Layout,
        preference: String? = nil
    ) async {
        isAnalyzing = true
        errorMessage = nil
        let targetPref = preference ?? userPreference

        do {
            // 1. Deterministic clearance check against Panero & Zelnik rules
            let violations = clearanceEngine.evaluate(room: room, layout: layout)
            self.detectedViolations = violations

            // 2. AI Reasoning and Solver Settings generation
            let rawResponse = try await diagnosticService.diagnose(
                room: room,
                layout: layout,
                violations: violations,
                userPreference: targetPref
            )

            // 3. Hallucination Gatekeeper: Validate all UUIDs against active scene
            let activeIDs = Set(layout.furnitures.filter { !$0.isArchived }.map(\.id))
            let validatedResponse = AIDiagnosticValidator.validate(rawResponse, activeFurnitureIDs: activeIDs)
            self.diagnosticResponse = validatedResponse

            // 4. Feed solver settings into Layout Engine to generate 3 layout variants
            let variants = layoutOptimizer.generateLayouts(
                for: room,
                from: layout,
                settings: validatedResponse.solverSettings
            )
            self.generatedLayouts = variants
            self.selectedLayout = variants.first

            // 5. Store clashing furniture IDs for 3D highlight rings
            let clashingIDs = Set(
                validatedResponse.insights
                    .filter { $0.sentiment == "-" }
                    .flatMap(\.involvedFurnitureIds)
            )
            self.highlightedFurnitureIDs = clashingIDs

        } catch {
            self.errorMessage = "Failed to complete AI spatial diagnostic: \(error.localizedDescription)"
        }

        isAnalyzing = false
    }

    public func selectInsight(_ insight: AIDiagnosticInsight) {
        self.highlightedFurnitureIDs = Set(insight.involvedFurnitureIds)
    }

    public func selectLayout(_ layout: Layout) {
        self.selectedLayout = layout
    }

    public func clearHighlights() {
        self.highlightedFurnitureIDs.removeAll()
    }
}
