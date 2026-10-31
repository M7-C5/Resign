//
//  AIDiagnosticService.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation
import FoundationModels

@MainActor
public protocol AIDiagnosticServiceProtocol {
    func diagnose(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        userPreference: RoomPreference
    ) async throws -> AIDiagnosticResponse

    /// Dynamic insight cards for one suggested layout. `violations` must be measured on `layout`.
    func generateLayoutInsights(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        preference: RoomPreference
    ) async -> [LayoutInsight]
}

@MainActor
public final class FoundationModelAIDiagnosticService: AIDiagnosticServiceProtocol {
    private let fallbackService: AIDiagnosticServiceProtocol

    public init(fallbackService: AIDiagnosticServiceProtocol? = nil) {
        self.fallbackService = fallbackService ?? RulebookAIDiagnosticService()
    }

    public func diagnose(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        userPreference: RoomPreference
    ) async throws -> AIDiagnosticResponse {
        let activeFurnitures = layout.furnitures.filter { !$0.isArchived }
        let activeIDs = Set(activeFurnitures.map(\.id))

        // Check if Apple Foundation Models are available on-device
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard !isTesting && SystemLanguageModel.default.isAvailable else {
            print("ℹ️ [Resign AI] SystemLanguageModel.default is disabled for testing or unavailable. Routing through RulebookAIDiagnosticService fallback.")
            return try await fallbackService.diagnose(
                room: room,
                layout: layout,
                violations: violations,
                userPreference: userPreference
            )
        }

        print("✨ [Resign AI] SystemLanguageModel.default.isAvailable is TRUE!")
        print("✨ [Resign AI] Dispatching prompt to Apple Foundation Model (LanguageModelSession)...")

        let prompt = RoomDiagnosticPromptBuilder.buildPrompt(
            room: room,
            layout: layout,
            violations: violations,
            userPreference: userPreference
        )

        let toolContext = SpatialToolContext(room: room, layout: layout)
        let tools = SpatialToolContext.makeTools(context: toolContext)

        let instructions = Instructions("""
        You are an expert architectural ergonomics and interior layout reasoning engine operating under the Panero & Zelnik standard ("Human Dimension & Interior Space").
        You have spatial tools to measure clearances, register user constraints, and preview layout variants.
        Always output raw valid JSON adhering strictly to the required schema. Do not output markdown code blocks or explanatory commentary outside the JSON payload.
        """)

        let session = LanguageModelSession(tools: tools, instructions: instructions)

        var rawResponseContent: String = ""
        do {
            let response = try await session.respond(to: prompt)
            rawResponseContent = response.content
            print("📥 [Resign AI] Raw Foundation Model output received (\(response.content.count) chars).")
            let sanitizedJSON = Self.sanitizeJSONResponse(response.content)

            guard let jsonData = sanitizedJSON.data(using: .utf8) else {
                print("⚠️ [Resign AI] Failed to convert sanitized output to UTF-8 data. Using fallback.")
                return try await fallbackService.diagnose(
                    room: room,
                    layout: layout,
                    violations: violations,
                    userPreference: userPreference
                )
            }

            var decodedResponse = try JSONDecoder().decode(AIDiagnosticResponse.self, from: jsonData)
            decodedResponse.engineSource = .appleIntelligence

            // Deterministic backstop: merge derived constraints and tool context constraints
            let combinedConstraints = userPreference.derivedConstraints
                .merged(with: toolContext.constraints)
                .merged(with: decodedResponse.solverSettings.constraints)
            decodedResponse.solverSettings.constraints = combinedConstraints

            // Deterministic backstop: merge freeText pins, toolContext pins, and decoded pins
            var mergedPins = Set(decodedResponse.solverSettings.pinnedItemIds)
            for id in toolContext.pinnedItemIDs { mergedPins.insert(id) }
            for id in RulebookAIDiagnosticService.extractRequestedPinnedItemIDs(from: userPreference.freeText, in: activeFurnitures) {
                mergedPins.insert(id)
            }
            decodedResponse.solverSettings.pinnedItemIds = Array(mergedPins)

            print("✅ [Resign AI] Successfully parsed Foundation Model response with \(decodedResponse.insights.count) insights.")
            return AIDiagnosticValidator.validate(decodedResponse, activeFurnitureIDs: activeIDs)
        } catch {
            print("⚠️ [Resign AI] Foundation Model error or decode failure: \(error). Falling back to Rulebook.")
            if !rawResponseContent.isEmpty {
                print("📄 [Resign AI] Raw model response was:\n\(rawResponseContent)")
            }
            return try await fallbackService.diagnose(
                room: room,
                layout: layout,
                violations: violations,
                userPreference: userPreference
            )
        }
    }

    public func generateLayoutInsights(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        preference: RoomPreference
    ) async -> [LayoutInsight] {
        let engine = LayoutInsightEngine()
        let candidates = engine.candidates(room: room, layout: layout, violations: violations)
        guard !candidates.isEmpty else { return [] }

        guard SystemLanguageModel.default.isAvailable else {
            return await fallbackService.generateLayoutInsights(
                room: room, layout: layout, violations: violations, preference: preference
            )
        }

        let prompt = RoomDiagnosticPromptBuilder.buildLayoutInsightsPrompt(
            layoutName: layout.name,
            candidates: candidates,
            preference: preference
        )
        let session = LanguageModelSession(instructions: Instructions("""
        You write short, factual interior layout insight cards. Output raw valid JSON only, matching the requested schema. Never add claims beyond the verified facts provided.
        """))

        do {
            let response = try await session.respond(to: prompt)
            let sanitized = Self.sanitizeJSONResponse(response.content)
            guard let data = sanitized.data(using: .utf8) else {
                return engine.rank(candidates, preference: preference)
            }
            let decoded = try JSONDecoder().decode(LayoutInsightsResponse.self, from: data)
            return LayoutInsightValidator.validate(decoded.insights, candidates: candidates, preference: preference)
        } catch {
            print("⚠️ [Resign AI] Layout insight generation failed: \(error). Using deterministic insights.")
            return engine.rank(candidates, preference: preference)
        }
    }

    nonisolated public static func sanitizeJSONResponse(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json") {
            text = String(text.dropFirst(7))
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst(3))
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            text = String(text[firstBrace...lastBrace])
        }

        return text
    }
}

@MainActor
public final class RulebookAIDiagnosticService: AIDiagnosticServiceProtocol {
    public init() {}

    public func diagnose(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        userPreference: RoomPreference
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
                    sentiment: "-",
                    severity: violation.severity
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

        // 3. Synthesize custom user preference rules from free text
        let customRules = Self.extractCustomUserRules(from: userPreference.freeText, in: activeFurnitures, room: room)
        insights.append(contentsOf: customRules)

        // 4. Formulate Solver Settings
        // Only pin furniture pieces the user explicitly requested to keep fixed or stuck.
        var pinned: [UUID] = []
        let userRequestedPins = Self.extractRequestedPinnedItemIDs(from: userPreference.freeText, in: activeFurnitures)
        for id in userRequestedPins where !pinned.contains(id) {
            pinned.append(id)
        }

        let mustHaves = activeFurnitures.map(\.id)

        // Tune goal weights from the user's selected/inferred problems; fall back to
        // keyword matching on free text for legacy goal phrases.
        let weights: GoalWeights
        if let derived = userPreference.suggestedGoalWeights {
            weights = derived
        } else {
            let prefLower = userPreference.freeText.lowercased()
            if prefLower.contains("spacious") || prefLower.contains("open") {
                weights = GoalWeights(spacious: 0.9, balanced: 0.4, reachable: 0.6)
            } else if prefLower.contains("ergonomic") || prefLower.contains("work") || prefLower.contains("productivity") {
                weights = GoalWeights(spacious: 0.6, balanced: 0.7, reachable: 0.9)
            } else if prefLower.contains("rest") || prefLower.contains("cozy") || prefLower.contains("sanctuary") {
                weights = GoalWeights(spacious: 0.5, balanced: 0.8, reachable: 0.7)
            } else {
                weights = GoalWeights(spacious: 0.7, balanced: 0.6, reachable: 0.7)
            }
        }

        let rawResponse = AIDiagnosticResponse(
            insights: insights,
            solverSettings: SolverSettings(
                pinnedItemIds: pinned,
                mustHaveItemIds: mustHaves,
                goalWeights: weights,
                constraints: userPreference.derivedConstraints
            ),
            engineSource: .rulebookFallback
        )

        // 4. Validate through gatekeeper to guarantee no hallucinated IDs reach scene
        return AIDiagnosticValidator.validate(rawResponse, activeFurnitureIDs: activeIDs)
    }

    public func generateLayoutInsights(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        preference: RoomPreference
    ) async -> [LayoutInsight] {
        let engine = LayoutInsightEngine()
        return engine.rank(
            engine.candidates(room: room, layout: layout, violations: violations),
            preference: preference
        )
    }

    /// Detects if the user asked in free text to keep, stick, or pin specific furniture pieces in place.
    public static func extractRequestedPinnedItemIDs(from text: String, in furnitures: [Furniture]) -> [UUID] {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return [] }

        // Intent markers indicating the user wants an item kept, fixed, or stuck
        let pinIntents = [
            "keep", "stick", "stay", "fixed", "leave", "remain", "hold",
            "don't move", "dont move", "do not move", "no move", "same place",
            "same spot", "same position", "against the wall", "on the wall",
            "to the wall", "where it is", "pinned"
        ]

        let hasIntent = pinIntents.contains { lower.contains($0) }
        guard hasIntent else { return [] }

        var requestedIDs: [UUID] = []

        for item in furnitures where !item.isArchived {
            let cat = item.category.lowercased()
            let name = item.name.lowercased()

            var itemKeywords: [String] = [name, cat]
            if cat == "television" || name.contains("tv") {
                itemKeywords.append(contentsOf: ["tv", "television", "console", "screen"])
            } else if cat == "bed" || name.contains("bed") {
                itemKeywords.append(contentsOf: ["bed", "queen bed", "mattress"])
            } else if cat == "desk" || name.contains("desk") {
                itemKeywords.append(contentsOf: ["desk", "workstation", "table"])
            } else if cat == "sofa" || name.contains("sofa") {
                itemKeywords.append(contentsOf: ["sofa", "couch", "lounge"])
            } else if cat == "chair" || name.contains("chair") || name.contains("stool") {
                itemKeywords.append(contentsOf: ["chair", "office chair", "stool"])
            } else if cat == "closet" || cat == "wardrobe" || name.contains("closet") || name.contains("wardrobe") {
                itemKeywords.append(contentsOf: ["closet", "wardrobe", "armoire"])
            }

            let mentionsItem = itemKeywords.contains { kw in
                lower.contains(kw)
            }

            if mentionsItem {
                requestedIDs.append(item.id)
            }
        }

        return requestedIDs
    }

    /// Converts user free-text words and phrases into explicit, actionable diagnostic rules and insight cards.
    public static func extractCustomUserRules(
        from text: String,
        in furnitures: [Furniture],
        room: Room
    ) -> [AIDiagnosticInsight] {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return [] }

        var rules: [AIDiagnosticInsight] = []

        // 1. Pinned / Fixed Request Rule
        let pinnedIDs = extractRequestedPinnedItemIDs(from: text, in: furnitures)
        if !pinnedIDs.isEmpty {
            let pinnedNames = furnitures.filter { pinnedIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
            rules.append(
                AIDiagnosticInsight(
                    ruleId: "R_CUSTOM",
                    involvedFurnitureIds: pinnedIDs,
                    explanation: "Custom Rule Applied: Keeping \(pinnedNames) fixed in place.",
                    suggestedFix: "Room optimizer keeps \(pinnedNames) anchored while rearranging remaining furniture for optimal flow.",
                    sentiment: "+",
                    title: "Preference"
                )
            )
        }

        // 2. Daylight & Window Workstation Rule
        if UserConstraintParser.daylightTriggers.contains(where: { lower.contains($0) }) {
            let deskItems = furnitures.filter { $0.category == "desk" || $0.name.localizedCaseInsensitiveContains("desk") }
            if !deskItems.isEmpty {
                rules.append(
                    AIDiagnosticInsight(
                        ruleId: "R_CUSTOM",
                        involvedFurnitureIds: deskItems.map(\.id),
                        explanation: "Custom Rule Applied: Prioritizing window daylight alignment for your workstation.",
                        suggestedFix: "Workstation anchored to window perimeter wall.",
                        sentiment: "+",
                        title: "Daylight"
                    )
                )
            }
        }

        // 3. Spacious Walkway & Circulation Rule
        if UserConstraintParser.spaceTriggers.contains(where: { lower.contains($0) }) {
            rules.append(
                AIDiagnosticInsight(
                    ruleId: "R_CUSTOM",
                    involvedFurnitureIds: [],
                    explanation: "Custom Rule Applied: Maximizing open walkway circulation and central plaza clearance.",
                    suggestedFix: "Furniture is flush-anchored to perimeter walls with primary pathways widened past 92 cm.",
                    sentiment: "+",
                    title: "Spacious"
                )
            )
        }

        // 4. Media & TV Sightline Rule
        if UserConstraintParser.mediaTriggers.contains(where: { lower.contains($0) }) {
            let tvAndSofa = furnitures.filter {
                $0.category == "television" || $0.category == "sofa" ||
                $0.name.localizedCaseInsensitiveContains("tv") || $0.name.localizedCaseInsensitiveContains("sofa")
            }
            if !tvAndSofa.isEmpty {
                rules.append(
                    AIDiagnosticInsight(
                        ruleId: "R_CUSTOM",
                        involvedFurnitureIds: tvAndSofa.map(\.id),
                        explanation: "Custom Rule Applied: Guaranteed clear sightline between lounge seating and TV.",
                        suggestedFix: "Sofa is centered directly opposite the TV console with a clear viewing corridor.",
                        sentiment: "+",
                        title: "Sightline"
                    )
                )
            }
        }

        // 5. Restful Sanctuary / Cozy Bedroom Rule
        if UserConstraintParser.cozyTriggers.contains(where: { lower.contains($0) }) {
            let bedItems = furnitures.filter { $0.category == "bed" || $0.name.localizedCaseInsensitiveContains("bed") }
            if !bedItems.isEmpty {
                rules.append(
                    AIDiagnosticInsight(
                        ruleId: "R_CUSTOM",
                        involvedFurnitureIds: bedItems.map(\.id),
                        explanation: "Custom Rule Applied: Quiet acoustic zoning for your sleeping area.",
                        suggestedFix: "Bed is tucked into the most protected corner away from entry door swing and noise.",
                        sentiment: "+",
                        title: "Sanctuary"
                    )
                )
            }
        }

        return rules
    }
}
