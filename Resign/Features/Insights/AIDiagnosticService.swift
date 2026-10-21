//
//  AIDiagnosticService.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation

@MainActor
public protocol AIDiagnosticServiceProtocol {
    func diagnose(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        userPreference: String
    ) async throws -> AIDiagnosticResponse
}

@MainActor
public final class RulebookAIDiagnosticService: AIDiagnosticServiceProtocol {
    public init() {}

    public func diagnose(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        userPreference: String
    ) async throws -> AIDiagnosticResponse {
        let activeFurnitures = layout.furnitures.filter { !$0.isArchived }
        let activeIDs = Set(activeFurnitures.map(\.id))

        var insights: [AIDiagnosticInsight] = []

        // 1. Synthesize insights from measured violations
        for violation in violations {
            let itemNames = activeFurnitures.filter { violation.itemIds.contains($0.id) }.map(\.name).joined(separator: " & ")
            let displayName = itemNames.isEmpty ? "furniture" : itemNames

            let explanation: String
            let suggestedFix: String

            switch violation.ruleId {
            case PaneroZelnikRule.walkwayCritical:
                explanation = "Severe circulation pinch-point between \(displayName): measured clearance is only \(Int(violation.measuredClearanceCm.rounded())) cm. Panero & Zelnik (R1) specifies a hard 76.2 cm absolute minimum."
                suggestedFix = "Shift \(displayName) towards perimeter walls to restore a continuous 90+ cm circulation spine."
            case PaneroZelnikRule.walkwayRecommended:
                explanation = "Passage near \(displayName) is \(Int(violation.measuredClearanceCm.rounded())) cm. While above critical failure, it falls short of Panero & Zelnik's 91.4 cm (R2) recommended comfort corridor."
                suggestedFix = "Widen spacing to 92 cm to allow two occupants to cross without turning sideways."
            case PaneroZelnikRule.deskRearClearance:
                explanation = "Seated egress restricted at \(displayName): chair pull-back zone is \(Int(violation.measuredClearanceCm.rounded())) cm, below the 76.2 cm Panero & Zelnik (R3) threshold."
                suggestedFix = "Pull the desk forward or clear rear obstruction so the task chair can push back smoothly."
            case PaneroZelnikRule.bedOperationalZone:
                explanation = "Perimeter bed-making friction around \(displayName): side access is \(Int(violation.measuredClearanceCm.rounded())) cm, violating Panero & Zelnik (R4) minimum of 66–99 cm."
                suggestedFix = "Maintain at least 66 cm clearance on accessible bed sides for ergonomic bedding changes."
            case PaneroZelnikRule.bedStorageZone:
                explanation = "Drawer clearance constricted for \(displayName): current spacing is \(Int(violation.measuredClearanceCm.rounded())) cm, under Panero & Zelnik (R5) 116–157 cm storage extension zone."
                suggestedFix = "Provide at least 116 cm unobstructed buffer along under-bed storage drawers."
            case PaneroZelnikRule.doorSwingUnobstructed:
                explanation = "Direct door swing collision: \(displayName) intrudes into entry door arc. Panero & Zelnik (R6) mandates 100% unobstructed door clearance."
                suggestedFix = "Relocate \(displayName) completely out of the door inward swing zone."
            default:
                explanation = violation.message
                suggestedFix = "Reposition furniture to satisfy standard clearance thresholds."
            }

            insights.append(
                AIDiagnosticInsight(
                    ruleId: violation.ruleId,
                    involvedFurnitureIds: violation.itemIds,
                    explanation: explanation,
                    suggestedFix: suggestedFix,
                    sentiment: "-"
                )
            )
        }

        // 2. Synthesize positive spatial synergy if applicable
        let hasWindow = room.openings.contains { $0.type.lowercased() == "window" }
        if hasWindow {
            insights.append(
                AIDiagnosticInsight(
                    ruleId: "R7",
                    involvedFurnitureIds: activeFurnitures.filter { $0.category == "desk" }.map(\.id),
                    explanation: "Natural daylight alignment: Workstation benefits from ambient daylighting.",
                    suggestedFix: "Orient computer screen perpendicular to window glass to prevent specular glare.",
                    sentiment: "+"
                )
            )
        }

        // 3. Formulate Solver Settings
        // Heavy/architectural items (wardrobe, fixed closet) default to pinned
        let pinned = activeFurnitures.filter {
            $0.category == "closet" || $0.category == "wardrobe" || $0.name.localizedCaseInsensitiveContains("closet")
        }.map(\.id)

        let mustHaves = activeFurnitures.map(\.id)

        // Tune goal weights based on user preference
        let prefLower = userPreference.lowercased()
        let weights: GoalWeights
        if prefLower.contains("spacious") || prefLower.contains("open") {
            weights = GoalWeights(spacious: 0.9, balanced: 0.4, reachable: 0.6)
        } else if prefLower.contains("ergonomic") || prefLower.contains("work") || prefLower.contains("productivity") {
            weights = GoalWeights(spacious: 0.6, balanced: 0.7, reachable: 0.9)
        } else if prefLower.contains("rest") || prefLower.contains("cozy") || prefLower.contains("sanctuary") {
            weights = GoalWeights(spacious: 0.5, balanced: 0.8, reachable: 0.7)
        } else {
            weights = GoalWeights(spacious: 0.7, balanced: 0.6, reachable: 0.7)
        }

        let rawResponse = AIDiagnosticResponse(
            insights: insights,
            solverSettings: SolverSettings(
                pinnedItemIds: pinned,
                mustHaveItemIds: mustHaves,
                goalWeights: weights
            )
        )

        // 4. Validate through gatekeeper to guarantee no hallucinated IDs reach scene
        return AIDiagnosticValidator.validate(rawResponse, activeFurnitureIDs: activeIDs)
    }
}
