//
//  LayoutInsight.swift
//  Resign
//
//  Dynamic per-layout insight cards ("Spacious circulation", "Defined zones", ...).
//

import Foundation

public struct LayoutInsight: Identifiable, Codable, Equatable, Sendable {
    public static let maxTitleLength = 30
    public static let maxDetailLength = 90

    public var id: UUID
    public var category: LayoutInsightCategory
    /// Short card title.
    public var title: String
    /// One short sentence shown under the title.
    public var detail: String
    /// "+" strength, "-" weakness.
    public var sentiment: String
    /// User-reported problems this insight speaks to (positive insights only).
    public var addressedProblems: [ProblemKeyword]

    public init(
        id: UUID = UUID(),
        category: LayoutInsightCategory,
        title: String,
        detail: String,
        sentiment: String = "+",
        addressedProblems: [ProblemKeyword] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.sentiment = sentiment
        self.addressedProblems = addressedProblems
    }

    enum CodingKeys: String, CodingKey {
        case id, category, title, detail, sentiment, addressedProblems
    }

    /// Throws only when `category` is missing or unknown; everything else is repaired.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.category = try container.decode(LayoutInsightCategory.self, forKey: .category)
        self.title = (try? container.decode(String.self, forKey: .title)) ?? ""
        self.detail = (try? container.decode(String.self, forKey: .detail)) ?? ""
        self.sentiment = (try? container.decode(String.self, forKey: .sentiment)) ?? "+"
        let raw = (try? container.decode([String].self, forKey: .addressedProblems)) ?? []
        self.addressedProblems = raw.compactMap(ProblemKeyword.init(rawValue:))
    }
}

/// Decoding wrapper for the model's layout-insight JSON. One malformed card never
/// discards the others.
public struct LayoutInsightsResponse: Decodable, Sendable {
    public var insights: [LayoutInsight]

    private struct Lossy: Decodable {
        let value: LayoutInsight?
        init(from decoder: Decoder) throws {
            value = try? LayoutInsight(from: decoder)
        }
    }

    enum CodingKeys: String, CodingKey { case insights }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let boxes = (try? container.decode([Lossy].self, forKey: .insights)) ?? []
        self.insights = boxes.compactMap(\.value)
    }
}

// MARK: - Validation Gatekeeper

public struct LayoutInsightValidator: Sendable {
    /// The model may only phrase and prioritise facts the deterministic engine verified.
    /// Unknown categories are dropped, sentiment is forced to the verified one, text is
    /// length-clamped, and only one card per category survives.
    public static func validate(
        _ proposed: [LayoutInsight],
        candidates: [LayoutInsight],
        preference: RoomPreference,
        limit: Int = LayoutInsightEngine.maxInsights
    ) -> [LayoutInsight] {
        let verified = Dictionary(candidates.map { ($0.category, $0) }, uniquingKeysWith: { first, _ in first })
        let allowedProblems = Set(preference.effectiveKeywords)
        var seen = Set<LayoutInsightCategory>()
        var result: [LayoutInsight] = []

        for insight in proposed {
            guard let fact = verified[insight.category], seen.insert(insight.category).inserted else { continue }
            let title = String(insight.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LayoutInsight.maxTitleLength))
            let detail = String(insight.detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LayoutInsight.maxDetailLength))
            guard !title.isEmpty, !detail.isEmpty else { continue }
            let problems = insight.addressedProblems.filter {
                allowedProblems.contains($0) && $0.relatedCategories.contains(insight.category)
            }
            result.append(
                LayoutInsight(
                    id: insight.id,
                    category: insight.category,
                    title: title,
                    detail: detail,
                    sentiment: fact.sentiment,
                    addressedProblems: fact.sentiment == "+" ? problems : []
                )
            )
        }

        guard !result.isEmpty else {
            return LayoutInsightEngine().rank(candidates, preference: preference, limit: limit)
        }
        return Array(result.prefix(limit))
    }
}
