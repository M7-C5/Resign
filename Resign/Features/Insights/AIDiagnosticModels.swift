//
//  AIDiagnosticModels.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation

// MARK: - Compact DTOs for LLM Input

public struct CompactRoomItem: Codable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    public var widthCm: Int
    public var lengthCm: Int
    public var heightCm: Int
    public var posXCm: Int
    public var posZCm: Int
    public var yawDegrees: Int

    public init(
        id: String,
        name: String,
        role: String,
        widthCm: Int,
        lengthCm: Int,
        heightCm: Int,
        posXCm: Int,
        posZCm: Int,
        yawDegrees: Int
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.widthCm = widthCm
        self.lengthCm = lengthCm
        self.heightCm = heightCm
        self.posXCm = posXCm
        self.posZCm = posZCm
        self.yawDegrees = yawDegrees
    }
}

public struct CompactRoomOpening: Codable, Sendable {
    public var type: String
    public var widthCm: Int
    public var posXCm: Int
    public var posZCm: Int

    public init(type: String, widthCm: Int, posXCm: Int, posZCm: Int) {
        self.type = type
        self.widthCm = widthCm
        self.posXCm = posXCm
        self.posZCm = posZCm
    }
}

public struct CompactViolation: Codable, Sendable {
    public var ruleId: String
    public var itemIds: [String]
    public var measuredCm: Int
    public var requiredCm: Int
    public var issue: String

    public init(ruleId: String, itemIds: [String], measuredCm: Int, requiredCm: Int, issue: String) {
        self.ruleId = ruleId
        self.itemIds = itemIds
        self.measuredCm = measuredCm
        self.requiredCm = requiredCm
        self.issue = issue
    }
}

public struct CompactRoomPayload: Codable, Sendable {
    public var roomDimensionsCm: [Int] // [width, length, height]
    public var openings: [CompactRoomOpening]
    public var items: [CompactRoomItem]
    public var measuredViolations: [CompactViolation]
    public var userPreference: String

    public init(
        roomDimensionsCm: [Int],
        openings: [CompactRoomOpening],
        items: [CompactRoomItem],
        measuredViolations: [CompactViolation],
        userPreference: String
    ) {
        self.roomDimensionsCm = roomDimensionsCm
        self.openings = openings
        self.items = items
        self.measuredViolations = measuredViolations
        self.userPreference = userPreference
    }
}

// MARK: - LLM Diagnostic Output Contracts

public struct AIDiagnosticInsight: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var ruleId: String
    public var involvedFurnitureIds: [UUID]
    public var explanation: String
    public var suggestedFix: String
    public var sentiment: String // "+" for positive opportunity, "-" for clash/violation

    public init(
        id: UUID = UUID(),
        ruleId: String,
        involvedFurnitureIds: [UUID],
        explanation: String,
        suggestedFix: String,
        sentiment: String = "-"
    ) {
        self.id = id
        self.ruleId = ruleId
        self.involvedFurnitureIds = involvedFurnitureIds
        self.explanation = explanation
        self.suggestedFix = suggestedFix
        self.sentiment = sentiment
    }
}

public struct GoalWeights: Codable, Equatable, Sendable {
    public var spacious: Double
    public var balanced: Double
    public var reachable: Double

    public init(spacious: Double = 0.5, balanced: Double = 0.5, reachable: Double = 0.5) {
        self.spacious = spacious
        self.balanced = balanced
        self.reachable = reachable
    }
}

public struct SolverSettings: Codable, Equatable, Sendable {
    public var pinnedItemIds: [UUID]
    public var mustHaveItemIds: [UUID]
    public var goalWeights: GoalWeights

    public init(
        pinnedItemIds: [UUID] = [],
        mustHaveItemIds: [UUID] = [],
        goalWeights: GoalWeights = GoalWeights()
    ) {
        self.pinnedItemIds = pinnedItemIds
        self.mustHaveItemIds = mustHaveItemIds
        self.goalWeights = goalWeights
    }
}

public struct AIDiagnosticResponse: Codable, Equatable, Sendable {
    public var insights: [AIDiagnosticInsight]
    public var solverSettings: SolverSettings

    public init(insights: [AIDiagnosticInsight], solverSettings: SolverSettings) {
        self.insights = insights
        self.solverSettings = solverSettings
    }
}

// MARK: - Hallucination Sanitation & Validation Gatekeeper

public struct AIDiagnosticValidator: Sendable {
    public static func validate(
        _ response: AIDiagnosticResponse,
        activeFurnitureIDs: Set<UUID>
    ) -> AIDiagnosticResponse {
        // 1. Sanitize Insights: drop any ID that is not in the active furniture set
        let sanitizedInsights: [AIDiagnosticInsight] = response.insights.map { insight in
            let validInvolved = insight.involvedFurnitureIds.filter { activeFurnitureIDs.contains($0) }
            return AIDiagnosticInsight(
                id: insight.id,
                ruleId: insight.ruleId,
                involvedFurnitureIds: validInvolved,
                explanation: insight.explanation,
                suggestedFix: insight.suggestedFix,
                sentiment: insight.sentiment
            )
        }

        // 2. Sanitize Solver Settings: filter pins and must-haves
        let validPins = response.solverSettings.pinnedItemIds.filter { activeFurnitureIDs.contains($0) }
        let validMustHaves = response.solverSettings.mustHaveItemIds.filter { activeFurnitureIDs.contains($0) }

        // 3. Normalize & clamp goal weights into [0.0, 1.0]
        let rawWeights = response.solverSettings.goalWeights
        let clampedWeights = GoalWeights(
            spacious: min(max(rawWeights.spacious, 0.0), 1.0),
            balanced: min(max(rawWeights.balanced, 0.0), 1.0),
            reachable: min(max(rawWeights.reachable, 0.0), 1.0)
        )

        return AIDiagnosticResponse(
            insights: sanitizedInsights,
            solverSettings: SolverSettings(
                pinnedItemIds: validPins,
                mustHaveItemIds: validMustHaves,
                goalWeights: clampedWeights
            )
        )
    }
}
