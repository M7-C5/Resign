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

/// Structured form of the user's preference step. Free text is untrusted data, never instructions.
public struct CompactUserPreference: Codable, Equatable, Sendable {
    public var reportedProblems: [String]
    public var inferredProblems: [String]
    public var freeText: String
    public var suggestedGoalWeights: GoalWeights?

    public init(
        reportedProblems: [String],
        inferredProblems: [String],
        freeText: String,
        suggestedGoalWeights: GoalWeights?
    ) {
        self.reportedProblems = reportedProblems
        self.inferredProblems = inferredProblems
        self.freeText = freeText
        self.suggestedGoalWeights = suggestedGoalWeights
    }

    public init(_ preference: RoomPreference) {
        self.init(
            reportedProblems: preference.selectedKeywords.map(\.title),
            inferredProblems: preference.inferredKeywords.map(\.title),
            freeText: preference.freeText,
            suggestedGoalWeights: preference.suggestedGoalWeights
        )
    }
}

public struct CompactRoomPayload: Codable, Sendable {
    public var roomDimensionsCm: [Int] // [width, length, height]
    public var openings: [CompactRoomOpening]
    public var items: [CompactRoomItem]
    public var measuredViolations: [CompactViolation]
    public var userPreference: CompactUserPreference

    public init(
        roomDimensionsCm: [Int],
        openings: [CompactRoomOpening],
        items: [CompactRoomItem],
        measuredViolations: [CompactViolation],
        userPreference: CompactUserPreference
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
    /// One or two word card label, e.g. "Narrow", "Desk", "Window".
    public var title: String
    /// Only meaningful for "-" insights.
    public var severity: ViolationSeverity?

    public static func defaultTitle(forRule ruleId: String) -> String {
        switch ruleId {
        case PaneroZelnikRule.walkwayCritical, PaneroZelnikRule.walkwayRecommended: return "Narrow"
        case PaneroZelnikRule.deskRearClearance: return "Desk"
        case PaneroZelnikRule.bedOperationalZone, PaneroZelnikRule.bedStorageZone: return "Bed"
        case PaneroZelnikRule.doorSwingUnobstructed: return "Door"
        case "R7": return "Window"
        case "R_CUSTOM": return "Preference"
        default: return "Layout"
        }
    }

    public init(
        id: UUID = UUID(),
        ruleId: String,
        involvedFurnitureIds: [UUID],
        explanation: String,
        suggestedFix: String,
        sentiment: String = "-",
        title: String? = nil,
        severity: ViolationSeverity? = nil
    ) {
        self.id = id
        self.ruleId = ruleId
        self.involvedFurnitureIds = involvedFurnitureIds
        self.explanation = explanation
        self.suggestedFix = suggestedFix
        self.sentiment = sentiment
        self.title = title ?? Self.defaultTitle(forRule: ruleId)
        self.severity = sentiment == "-" ? (severity ?? .warning) : nil
    }

    enum CodingKeys: String, CodingKey {
        case id, ruleId, involvedFurnitureIds, explanation, suggestedFix, sentiment, title, severity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.ruleId = (try? container.decode(String.self, forKey: .ruleId)) ?? "R1"

        if let uuids = try? container.decode([UUID].self, forKey: .involvedFurnitureIds) {
            self.involvedFurnitureIds = uuids
        } else if let strings = try? container.decode([String].self, forKey: .involvedFurnitureIds) {
            self.involvedFurnitureIds = strings.compactMap { UUID(uuidString: $0) }
        } else {
            self.involvedFurnitureIds = []
        }

        self.explanation = (try? container.decode(String.self, forKey: .explanation)) ?? ""
        self.suggestedFix = (try? container.decode(String.self, forKey: .suggestedFix)) ?? ""
        self.sentiment = (try? container.decode(String.self, forKey: .sentiment)) ?? "-"

        let rawTitle = ((try? container.decode(String.self, forKey: .title)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = rawTitle.isEmpty ? Self.defaultTitle(forRule: ruleId) : String(rawTitle.prefix(LayoutInsight.maxTitleLength))
        let decodedSeverity = try? container.decode(ViolationSeverity.self, forKey: .severity)
        self.severity = sentiment == "-" ? (decodedSeverity ?? .warning) : nil
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

    enum CodingKeys: String, CodingKey {
        case spacious, balanced, reachable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.spacious = (try? container.decode(Double.self, forKey: .spacious)) ?? 0.5
        self.balanced = (try? container.decode(Double.self, forKey: .balanced)) ?? 0.5
        self.reachable = (try? container.decode(Double.self, forKey: .reachable)) ?? 0.5
    }
}

public struct SolverSettings: Codable, Equatable, Sendable {
    public var pinnedItemIds: [UUID]
    public var mustHaveItemIds: [UUID]
    public var goalWeights: GoalWeights
    /// Structured user intent honoured by every generated variant.
    public var constraints: LayoutConstraints

    public init(
        pinnedItemIds: [UUID] = [],
        mustHaveItemIds: [UUID] = [],
        goalWeights: GoalWeights = GoalWeights(),
        constraints: LayoutConstraints = LayoutConstraints()
    ) {
        self.pinnedItemIds = pinnedItemIds
        self.mustHaveItemIds = mustHaveItemIds
        self.goalWeights = goalWeights
        self.constraints = constraints
    }

    enum CodingKeys: String, CodingKey {
        case pinnedItemIds, mustHaveItemIds, goalWeights, constraints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let uuids = try? container.decode([UUID].self, forKey: .pinnedItemIds) {
            self.pinnedItemIds = uuids
        } else if let strings = try? container.decode([String].self, forKey: .pinnedItemIds) {
            self.pinnedItemIds = strings.compactMap { UUID(uuidString: $0) }
        } else {
            self.pinnedItemIds = []
        }

        if let uuids = try? container.decode([UUID].self, forKey: .mustHaveItemIds) {
            self.mustHaveItemIds = uuids
        } else if let strings = try? container.decode([String].self, forKey: .mustHaveItemIds) {
            self.mustHaveItemIds = strings.compactMap { UUID(uuidString: $0) }
        } else {
            self.mustHaveItemIds = []
        }

        self.goalWeights = (try? container.decode(GoalWeights.self, forKey: .goalWeights)) ?? GoalWeights()
        self.constraints = (try? container.decode(LayoutConstraints.self, forKey: .constraints)) ?? LayoutConstraints()
    }
}

public enum DiagnosticEngineSource: String, Codable, Equatable, Sendable {
    case appleIntelligence = "Apple Intelligence"
    case rulebookFallback = "Rulebook Engine (Simulator)"
}

public struct AIDiagnosticResponse: Codable, Equatable, Sendable {
    public var insights: [AIDiagnosticInsight]
    public var solverSettings: SolverSettings
    public var engineSource: DiagnosticEngineSource

    public init(
        insights: [AIDiagnosticInsight],
        solverSettings: SolverSettings,
        engineSource: DiagnosticEngineSource = .appleIntelligence
    ) {
        self.insights = insights
        self.solverSettings = solverSettings
        self.engineSource = engineSource
    }

    enum CodingKeys: String, CodingKey {
        case insights, solverSettings, engineSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.insights = (try? container.decode([AIDiagnosticInsight].self, forKey: .insights)) ?? []
        self.solverSettings = (try? container.decode(SolverSettings.self, forKey: .solverSettings)) ?? SolverSettings()
        self.engineSource = (try? container.decodeIfPresent(DiagnosticEngineSource.self, forKey: .engineSource)) ?? .appleIntelligence
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
                sentiment: insight.sentiment,
                title: insight.title,
                severity: insight.severity
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
                goalWeights: clampedWeights,
                constraints: response.solverSettings.constraints
            ),
            engineSource: response.engineSource
        )
    }
}
