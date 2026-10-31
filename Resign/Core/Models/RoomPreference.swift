//
//  RoomPreference.swift
//  Resign
//
//  Domain contract for the "What's Not Working in Your Room?" preference step.
//

import Foundation

// MARK: - Insight Categories

/// Spatial themes a layout insight can speak about. Shared by the deterministic
/// insight engine, the AI validator, and (later) the insight card icons.
public enum LayoutInsightCategory: String, Codable, CaseIterable, Sendable {
    case circulation
    case zoning
    case naturalLight
    case access
    case privacy
    case storage
}

// MARK: - Problem Keywords

/// A selectable "problem" chip. Declaration order is the display order;
/// `isSuggested` chips are shown initially, the rest appear behind "See more".
public enum ProblemKeyword: String, Codable, CaseIterable, Identifiable, Sendable {
    // Initially suggested (design order)
    case noPrivacy
    case notEnoughSpace
    case poorLighting
    case noStorage
    case tooMuchClutter
    case hardToMove
    case tooDark
    case feelsCramped
    case uncomfortableSeating
    // Behind "See more"
    case noWorkspace
    case screenGlare
    case blockedEntrance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .noPrivacy: return "No privacy"
        case .notEnoughSpace: return "Not enough space"
        case .poorLighting: return "Poor lighting"
        case .noStorage: return "No storage"
        case .tooMuchClutter: return "Too much clutter"
        case .hardToMove: return "Hard to move"
        case .tooDark: return "Too dark"
        case .feelsCramped: return "Feels cramped"
        case .uncomfortableSeating: return "Uncomfortable seating"
        case .noWorkspace: return "No place to work"
        case .screenGlare: return "Screen glare"
        case .blockedEntrance: return "Blocked entrance"
        }
    }

    public var isSuggested: Bool {
        switch self {
        case .noWorkspace, .screenGlare, .blockedEntrance: return false
        default: return true
        }
    }

    public static var suggested: [ProblemKeyword] { allCases.filter(\.isSuggested) }
    public static var additional: [ProblemKeyword] { allCases.filter { !$0.isSuggested } }

    /// Insight categories that can actually help with this problem.
    public var relatedCategories: [LayoutInsightCategory] {
        switch self {
        case .noPrivacy: return [.privacy, .zoning]
        case .notEnoughSpace: return [.circulation]
        case .poorLighting, .tooDark, .screenGlare: return [.naturalLight]
        case .noStorage: return [.storage, .access]
        case .tooMuchClutter: return [.circulation, .storage]
        case .hardToMove: return [.circulation, .access]
        case .feelsCramped: return [.circulation, .zoning]
        case .uncomfortableSeating: return [.access, .zoning]
        case .noWorkspace: return [.zoning, .naturalLight]
        case .blockedEntrance: return [.access, .circulation]
        }
    }

    /// Layout variant that best answers this problem.
    var variantAffinity: String {
        switch self {
        case .poorLighting, .tooDark, .screenGlare, .noWorkspace:
            return LayoutOptimizerEngine.circadianName
        case .noPrivacy, .uncomfortableSeating:
            return LayoutOptimizerEngine.sanctuaryName
        case .notEnoughSpace, .feelsCramped, .hardToMove, .tooMuchClutter, .noStorage, .blockedEntrance:
            return LayoutOptimizerEngine.openFlowName
        }
    }

    /// Additive weight nudges for the layout solver.
    var goalBias: (spacious: Double, balanced: Double, reachable: Double) {
        switch self {
        case .notEnoughSpace, .feelsCramped: return (0.3, 0.0, 0.0)
        case .hardToMove, .blockedEntrance: return (0.2, 0.0, 0.2)
        case .tooMuchClutter: return (0.2, 0.2, 0.0)
        case .noStorage, .uncomfortableSeating: return (0.0, 0.0, 0.3)
        case .noPrivacy: return (0.0, 0.3, 0.0)
        case .poorLighting, .tooDark, .screenGlare: return (0.0, 0.2, 0.1)
        case .noWorkspace: return (0.0, 0.1, 0.3)
        }
    }

    /// Lowercased phrases in free text that imply this problem.
    fileprivate var triggerPhrases: [String] {
        switch self {
        case .noPrivacy: return ["privacy", "private", "exposed"]
        case .notEnoughSpace: return ["not enough space", "more space", "no space", "tight space", "too small"]
        case .poorLighting: return ["poor light", "lighting", "not enough light"]
        case .noStorage: return ["storage", "nowhere to put", "no place to put"]
        case .tooMuchClutter: return ["clutter", "messy"]
        case .hardToMove: return ["move around", "hard to move", "walk through", "get past", "squeeze"]
        case .tooDark: return ["dark", "dim", "gloomy"]
        case .feelsCramped: return ["cramped", "crowded", "claustrophob", "squeezed"]
        case .uncomfortableSeating: return ["uncomfortable chair", "uncomfortable seat", "seating", "back pain"]
        case .noWorkspace: return ["nowhere to work", "no desk", "no place to work", "workspace"]
        case .screenGlare: return ["glare", "reflection on"]
        case .blockedEntrance: return ["blocked door", "blocked entrance", "door is blocked", "door won't open"]
        }
    }
}

// MARK: - Room Preference

/// What the user told us is wrong with the room: selected chips plus optional free text.
/// String literals are accepted as free text so call sites and tests can stay terse.
public struct RoomPreference: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public static let maxFreeTextLength = 1000
    public static let none = RoomPreference()

    /// Unique, in selection order.
    public private(set) var selectedKeywords: [ProblemKeyword]
    /// Trimmed and clamped to `maxFreeTextLength` characters.
    public private(set) var freeText: String

    public init(selectedKeywords: [ProblemKeyword] = [], freeText: String = "") {
        var seen = Set<ProblemKeyword>()
        self.selectedKeywords = selectedKeywords.filter { seen.insert($0).inserted }
        self.freeText = Self.sanitize(freeText)
    }

    public init(stringLiteral value: String) {
        self.init(freeText: value)
    }

    public static func sanitize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxFreeTextLength))
    }

    public var isEmpty: Bool { selectedKeywords.isEmpty && freeText.isEmpty }

    /// Problems implied by the free text that the user did not tick explicitly.
    public var inferredKeywords: [ProblemKeyword] {
        let lower = freeText.lowercased()
        guard !lower.isEmpty else { return [] }
        let selected = Set(selectedKeywords)
        return ProblemKeyword.allCases.filter { keyword in
            !selected.contains(keyword) && keyword.triggerPhrases.contains { lower.contains($0) }
        }
    }

    /// Selected chips first, then inferred ones.
    public var effectiveKeywords: [ProblemKeyword] { selectedKeywords + inferredKeywords }

    /// Solver constraints implied by the chips the user ticked, the problems inferred from their
    /// free text, and the free text itself. Used identically on device and in the Simulator.
    public var derivedConstraints: LayoutConstraints {
        var constraints = UserConstraintParser.parse(freeText)
        for keyword in effectiveKeywords {
            switch keyword {
            case .noWorkspace, .poorLighting, .tooDark, .screenGlare:
                constraints.deskNearWindow = true
            case .notEnoughSpace, .feelsCramped, .hardToMove, .tooMuchClutter, .blockedEntrance:
                constraints.openCirculation = true
            case .noPrivacy:
                constraints.quietSleeping = true
            case .noStorage, .uncomfortableSeating:
                break
            }
        }
        return constraints
    }

    /// Insight categories the user cares about, most important first, unique.
    public var focusCategories: [LayoutInsightCategory] {
        var seen = Set<LayoutInsightCategory>()
        return effectiveKeywords.flatMap(\.relatedCategories).filter { seen.insert($0).inserted }
    }

    /// Anchor weights for the solver; nil when no problem can be derived.
    public var suggestedGoalWeights: GoalWeights? {
        let keywords = effectiveKeywords
        guard !keywords.isEmpty else { return nil }
        var spacious = 0.5, balanced = 0.5, reachable = 0.5
        for keyword in keywords {
            let bias = keyword.goalBias
            spacious += bias.spacious
            balanced += bias.balanced
            reachable += bias.reachable
        }
        return GoalWeights(
            spacious: min(spacious, 1.0),
            balanced: min(balanced, 1.0),
            reachable: min(reachable, 1.0)
        )
    }

    /// Layout variant that should be shown first. Selected chips outvote inferred ones.
    public var preferredVariantName: String? {
        var votes: [String: Double] = [:]
        for keyword in selectedKeywords { votes[keyword.variantAffinity, default: 0] += 1.0 }
        for keyword in inferredKeywords { votes[keyword.variantAffinity, default: 0] += 0.5 }
        guard let top = votes.values.max() else { return nil }
        let order = [
            LayoutOptimizerEngine.circadianName,
            LayoutOptimizerEngine.openFlowName,
            LayoutOptimizerEngine.sanctuaryName
        ]
        return order.first { votes[$0] == top }
    }
}
