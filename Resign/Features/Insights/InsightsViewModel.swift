//
//  InsightsViewModel.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation
import Observation
import SwiftData

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
    public var layoutInsights: [UUID: [LayoutInsight]] = [:]
    public var isAnalyzing: Bool = false
    public var errorMessage: String? = nil
    /// What the user said is wrong with the room (chips + free text).
    public var selectedKeywords: [ProblemKeyword] = []
    /// Raw editor text. Only clamped, never trimmed, so spaces survive while typing.
    public var userPreference: String = "" {
        didSet {
            if userPreference.count > RoomPreference.maxFreeTextLength {
                userPreference = String(userPreference.prefix(RoomPreference.maxFreeTextLength))
            }
        }
    }
    public var preference: RoomPreference {
        get { RoomPreference(selectedKeywords: selectedKeywords, freeText: userPreference) }
        set {
            selectedKeywords = newValue.selectedKeywords
            userPreference = newValue.freeText
        }
    }

    private let clearanceEngine: SpatialClearanceEngine
    private let diagnosticService: AIDiagnosticServiceProtocol
    private let layoutOptimizer: LayoutOptimizerEngine

    public init() {
        self.clearanceEngine = SpatialClearanceEngine()
        self.diagnosticService = FoundationModelAIDiagnosticService()
        self.layoutOptimizer = LayoutOptimizerEngine()
    }

    public init(
        clearanceEngine: SpatialClearanceEngine? = nil,
        diagnosticService: AIDiagnosticServiceProtocol? = nil,
        layoutOptimizer: LayoutOptimizerEngine? = nil
    ) {
        self.clearanceEngine = clearanceEngine ?? SpatialClearanceEngine()
        self.diagnosticService = diagnosticService ?? FoundationModelAIDiagnosticService()
        self.layoutOptimizer = layoutOptimizer ?? LayoutOptimizerEngine()
    }

    public func toggleKeyword(_ keyword: ProblemKeyword) {
        if let index = selectedKeywords.firstIndex(of: keyword) {
            selectedKeywords.remove(at: index)
        } else {
            selectedKeywords.append(keyword)
        }
    }

    public func loadRoom(_ room: Room, initialLayout: Layout? = nil) {
        self.currentRoom = room
        self.activeLayout = initialLayout ?? room.layouts.first
    }

    @MainActor
    public func runDiagnosticPipeline(
        for room: Room,
        in layout: Layout,
        preference: String?
    ) async {
        await runDiagnosticPipeline(
            for: room,
            in: layout,
            roomPreference: preference.map { RoomPreference(selectedKeywords: self.preference.selectedKeywords, freeText: $0) }
        )
    }

    @MainActor
    public func runDiagnosticPipeline(
        for room: Room,
        in layout: Layout,
        roomPreference: RoomPreference? = nil
    ) async {
        isAnalyzing = true
        errorMessage = nil
        let targetPref = roomPreference ?? preference

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

            // 4. Feed solver settings into Layout Engine to generate 3 layout variants,
            //    best fit for the user's problems first
            let generated = layoutOptimizer.generateLayouts(
                for: room,
                from: layout,
                settings: validatedResponse.solverSettings
            )
            let variants = Self.orderVariants(generated, preferredName: targetPref.preferredVariantName)
            self.generatedLayouts = variants
            self.selectedLayout = variants.first

            // 5. Dynamic, preference-aware insight cards per variant
            var insightsByLayout: [UUID: [LayoutInsight]] = [:]
            for variant in variants {
                let variantViolations = clearanceEngine.evaluate(room: room, layout: variant)
                let insights = await diagnosticService.generateLayoutInsights(
                    room: room,
                    layout: variant,
                    violations: variantViolations,
                    preference: targetPref
                )
                insightsByLayout[variant.id] = insights
                variant.insights = insights.map {
                    Insight(title: $0.title, type: $0.sentiment, detail: $0.detail)
                }
            }
            self.layoutInsights = insightsByLayout

            // 6. Store clashing furniture IDs for 3D highlight rings
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

    /// Moves the preferred variant to the front, keeping the others in their original order.
    static func orderVariants(_ variants: [Layout], preferredName: String?) -> [Layout] {
        guard let preferredName, let index = variants.firstIndex(where: { $0.name == preferredName }) else {
            return variants
        }
        var ordered = variants
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    public func selectInsight(_ insight: AIDiagnosticInsight) {
        self.highlightedFurnitureIDs = Set(insight.involvedFurnitureIds)
    }

    public func selectLayout(_ layout: Layout) {
        self.selectedLayout = layout
    }

    public func applySelectedLayout(context: ModelContext? = nil) {
        guard let selected = selectedLayout else { return }
        self.activeLayout = selected
        if let room = currentRoom {
            if !room.layouts.contains(where: { $0.id == selected.id }) {
                room.layouts.append(selected)
            }
            room.updatedAt = Date()
            try? context?.save()
        }
    }

    public func clearHighlights() {
        self.highlightedFurnitureIDs.removeAll()
    }
}
