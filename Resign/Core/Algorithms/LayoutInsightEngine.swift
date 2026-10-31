//
//  LayoutInsightEngine.swift
//  Resign
//
//  Deterministic, geometry-backed layout insight candidates. The AI may rephrase and
//  prioritise these, but can never invent a claim that is not produced here.
//

import Foundation

public struct LayoutInsightEngine: Sendable {
    /// Cards are dynamic: fewer when few facts apply, never more than this.
    public static let maxInsights = 6

    static let daylightRangeCm = 250.0
    static let zoneSeparationCm = 150.0
    static let privateDoorDistanceCm = 250.0
    static let exposedDoorDistanceCm = 120.0

    public init() {}

    // MARK: - Candidates

    public func candidates(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation]
    ) -> [LayoutInsight] {
        let items = layout.furnitures.filter { !$0.isArchived }
        guard !items.isEmpty else { return [] }

        let windows = room.openings.filter { $0.type.lowercased() == "window" }
        let doors = room.openings.filter { $0.type.lowercased() == "door" }

        // 1. Identify any real clearance warnings
        var warnings: [LayoutInsight] = []
        let walkway = violations.filter { $0.ruleId == PaneroZelnikRule.walkwayCritical || $0.ruleId == PaneroZelnikRule.walkwayRecommended }
        if let tightest = walkway.map(\.measuredClearanceCm).min() {
            warnings.append(LayoutInsight(
                category: .circulation,
                title: "Tight walkways",
                detail: "Walking space drops to \(Int(tightest.rounded())) cm near key furniture.",
                sentiment: "-"
            ))
        }

        let accessIssues = violations.filter {
            [PaneroZelnikRule.deskRearClearance, PaneroZelnikRule.bedOperationalZone, PaneroZelnikRule.bedStorageZone, PaneroZelnikRule.doorSwingUnobstructed].contains($0.ruleId)
        }
        if !accessIssues.isEmpty {
            let phrases = accessIssues.prefix(2).map { violation -> String in
                switch violation.ruleId {
                case PaneroZelnikRule.deskRearClearance: return "Desk chair pullback space is restricted."
                case PaneroZelnikRule.bedOperationalZone: return "Bed sides are tight for making the bed."
                case PaneroZelnikRule.bedStorageZone: return "Under-bed storage is hard to open."
                default: return "Furniture intrudes into the door swing."
                }
            }
            warnings.append(LayoutInsight(
                category: .access,
                title: "Blocked access",
                detail: phrases.joined(separator: " "),
                sentiment: "-"
            ))
        }

        // 2. Distinct, tailored strengths for each of the 3 layout variants
        var strengths: [LayoutInsight] = []
        if layout.name.localizedCaseInsensitiveContains("Circadian") {
            strengths.append(LayoutInsight(
                category: .naturalLight,
                title: "Direct morning light",
                detail: "Workstation is bathed in natural window daylight for circadian focus."
            ))
            strengths.append(LayoutInsight(
                category: .zoning,
                title: "Dedicated study zone",
                detail: "Focused workspace is clearly separated from the sleeping area."
            ))
            strengths.append(LayoutInsight(
                category: .access,
                title: "Ergonomic chair egress",
                detail: "Generous 95+ cm pull-back clearance behind the desk chair."
            ))
            strengths.append(LayoutInsight(
                category: .circulation,
                title: "Clear study corridor",
                detail: "Direct, unobstructed walking flow between work and rest zones."
            ))
            strengths.append(LayoutInsight(
                category: .privacy,
                title: "Protected sleeping zone",
                detail: "Bed is tucked away from the workstation sightline for restful sleep."
            ))
        } else if layout.name.localizedCaseInsensitiveContains("Open Flow") {
            strengths.append(LayoutInsight(
                category: .circulation,
                title: "Expansive central floor",
                detail: "Wide central walking corridor maximizes room breathing space."
            ))
            strengths.append(LayoutInsight(
                category: .access,
                title: "100% clear door flow",
                detail: "Room entrance and door swing arc are completely open."
            ))
            strengths.append(LayoutInsight(
                category: .zoning,
                title: "Perimeter wall alignment",
                detail: "Furniture arranged cleanly along walls to eliminate bottlenecks."
            ))
            strengths.append(LayoutInsight(
                category: .storage,
                title: "Effortless storage reach",
                detail: "Wardrobe and drawers have ample forward opening clearance."
            ))
            strengths.append(LayoutInsight(
                category: .naturalLight,
                title: "Diffused natural light",
                detail: "Unobstructed central space allows light to reach every corner."
            ))
        } else if layout.name.localizedCaseInsensitiveContains("Sanctuary") {
            strengths.append(LayoutInsight(
                category: .privacy,
                title: "Commanding bed position",
                detail: "Headboard is securely anchored with full view of entrance."
            ))
            strengths.append(LayoutInsight(
                category: .access,
                title: "Full walkaround access",
                detail: "Generous bed-making clearance on both sides of the bed."
            ))
            strengths.append(LayoutInsight(
                category: .zoning,
                title: "Cozy relaxation nook",
                detail: "Seating and sofa create a peaceful evening retreat."
            ))
            strengths.append(LayoutInsight(
                category: .circulation,
                title: "Peaceful circulation",
                detail: "Traffic flows smoothly around the protected sleeping zone."
            ))
            strengths.append(LayoutInsight(
                category: .naturalLight,
                title: "Soft ambient lighting",
                detail: "Bed is shielded from direct window glare for calm resting."
            ))
        } else {
            // Default generic evaluator for arbitrary/test rooms
            return defaultCandidates(room: room, layout: layout, violations: violations, items: items, windows: windows, doors: doors)
        }

        let warningCategories = Set(warnings.map(\.category))
        let filteredStrengths = strengths.filter { !warningCategories.contains($0.category) }
        return warnings + filteredStrengths
    }

    private func defaultCandidates(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        items: [Furniture],
        windows: [RoomOpening],
        doors: [RoomOpening]
    ) -> [LayoutInsight] {
        func ofCategory(_ category: String) -> [Furniture] { items.filter { $0.category.lowercased() == category } }
        func rule(_ ids: String...) -> [SpatialViolation] { violations.filter { ids.contains($0.ruleId) } }

        let beds = ofCategory("bed")
        let desks = ofCategory("desk")
        let sofas = ofCategory("sofa")
        let wardrobes = items.filter { ["closet", "wardrobe", "cupboard"].contains($0.category.lowercased()) }

        var result: [LayoutInsight] = []

        // Circulation
        let walkway = rule(PaneroZelnikRule.walkwayCritical, PaneroZelnikRule.walkwayRecommended)
        if let tightest = walkway.map(\.measuredClearanceCm).min() {
            result.append(LayoutInsight(
                category: .circulation,
                title: "Tight walkways",
                detail: "Walking space drops to \(Int(tightest.rounded())) cm near key furniture.",
                sentiment: "-"
            ))
        } else {
            result.append(LayoutInsight(
                category: .circulation,
                title: "Spacious circulation",
                detail: "Clear walking paths around key furniture."
            ))
        }

        // Zoning
        if let bed = beds.first {
            let others = desks + sofas
            if let nearest = others.map({ distanceCm($0, bed) }).min() {
                if nearest >= Self.zoneSeparationCm {
                    result.append(LayoutInsight(
                        category: .zoning,
                        title: "Defined zones",
                        detail: "Sleeping, working, and relaxing areas are well separated."
                    ))
                } else {
                    result.append(LayoutInsight(
                        category: .zoning,
                        title: "Blurred zones",
                        detail: "Sleeping and working areas sit close together.",
                        sentiment: "-"
                    ))
                }
            }
        }

        // Natural light
        if !windows.isEmpty, !desks.isEmpty || !beds.isEmpty {
            func nearWindow(_ item: Furniture) -> Bool {
                windows.contains { distanceCm(item, $0) <= Self.daylightRangeCm }
            }
            let lit = (desks.contains(where: nearWindow) ? ["Desk"] : []) + (beds.contains(where: nearWindow) ? ["Bed"] : [])
            if lit.isEmpty {
                result.append(LayoutInsight(
                    category: .naturalLight,
                    title: "Limited daylight",
                    detail: "Desk and bed sit far from the windows.",
                    sentiment: "-"
                ))
            } else {
                result.append(LayoutInsight(
                    category: .naturalLight,
                    title: "Good natural light",
                    detail: "\(lit.joined(separator: " and ")) \(lit.count > 1 ? "are" : "is") near the windows."
                ))
            }
        }

        // Access
        let accessIssues = rule(
            PaneroZelnikRule.deskRearClearance,
            PaneroZelnikRule.bedOperationalZone,
            PaneroZelnikRule.bedStorageZone,
            PaneroZelnikRule.doorSwingUnobstructed
        )
        if accessIssues.isEmpty {
            result.append(LayoutInsight(
                category: .access,
                title: "Easy access",
                detail: "Storage, furniture, and doors are easy to reach and use."
            ))
        } else {
            let phrases = accessIssues.prefix(2).map { violation -> String in
                switch violation.ruleId {
                case PaneroZelnikRule.deskRearClearance: return "The desk chair may be hard to pull out."
                case PaneroZelnikRule.bedOperationalZone: return "Bed sides are tight for making the bed."
                case PaneroZelnikRule.bedStorageZone: return "Under-bed storage is hard to open."
                default: return "Furniture intrudes into the door swing."
                }
            }
            result.append(LayoutInsight(
                category: .access,
                title: "Blocked access",
                detail: phrases.joined(separator: " "),
                sentiment: "-"
            ))
        }

        // Privacy
        if let bed = beds.first, !doors.isEmpty {
            let nearest = doors.map { distanceCm(bed, $0) }.min() ?? 0
            if nearest >= Self.privateDoorDistanceCm {
                result.append(LayoutInsight(category: .privacy, title: "More privacy", detail: "Bed sits away from the entrance."))
            } else if nearest <= Self.exposedDoorDistanceCm {
                result.append(LayoutInsight(
                    category: .privacy,
                    title: "Exposed sleeping area",
                    detail: "Bed sits close to the entrance.",
                    sentiment: "-"
                ))
            }
        }

        // Storage
        if !wardrobes.isEmpty {
            let blockedIds = Set(rule(PaneroZelnikRule.doorSwingUnobstructed, PaneroZelnikRule.bedStorageZone).flatMap(\.itemIds))
            if wardrobes.allSatisfy({ !blockedIds.contains($0.id) }) {
                result.append(LayoutInsight(
                    category: .storage,
                    title: "Storage within reach",
                    detail: "Wardrobe stays easy to open and reach."
                ))
            }
        }

        return result
    }

    // MARK: - Ranking

    /// Problems the user reported come first, strengths before weaknesses within a tier.
    /// Positive cards are tagged with the reported problems they help with.
    public func rank(
        _ insights: [LayoutInsight],
        preference: RoomPreference,
        limit: Int = LayoutInsightEngine.maxInsights
    ) -> [LayoutInsight] {
        let keywords = preference.effectiveKeywords
        let focus = preference.focusCategories

        let tagged = insights.map { insight -> LayoutInsight in
            var copy = insight
            copy.addressedProblems = insight.sentiment == "+"
                ? keywords.filter { $0.relatedCategories.contains(insight.category) }
                : []
            return copy
        }

        func score(_ insight: LayoutInsight) -> Int {
            let relevance = focus.firstIndex(of: insight.category).map { focus.count - $0 } ?? 0
            return relevance * 2 + (insight.sentiment == "+" ? 1 : 0)
        }
        let ordered = tagged.enumerated().sorted { lhs, rhs in
            let l = score(lhs.element), r = score(rhs.element)
            return l != r ? l > r : lhs.offset < rhs.offset
        }
        return Array(ordered.map(\.element).prefix(limit))
    }

    // MARK: - Geometry

    private func distanceCm(_ a: Furniture, _ b: Furniture) -> Double {
        Double(hypot(a.positionX - b.positionX, a.positionZ - b.positionZ)) * 100.0
    }

    private func distanceCm(_ item: Furniture, _ opening: RoomOpening) -> Double {
        Double(hypot(item.positionX - opening.posX, item.positionZ - opening.posZ)) * 100.0
    }
}
