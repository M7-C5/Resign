//
//  LayoutConstraints.swift
//  Resign
//
//  Structured user intent that the layout solver must honour in every variant.
//

import Foundation

/// Hard-to-miss, machine-readable intent. Produced deterministically from chips and free text
/// (`UserConstraintParser`) and, on supported devices, also by the Foundation Model via tools.
public struct LayoutConstraints: Codable, Equatable, Sendable {
    /// Work desk belongs next to the window (daylight / screen glare / "nowhere to work").
    public var deskNearWindow: Bool
    /// Keep walkways wide (cramped / hard to move / clutter / blocked entrance).
    public var openCirculation: Bool
    /// Bed goes to the quietest, most private spot, far from the entrance.
    public var quietSleeping: Bool
    /// Nothing may stand between the TV and the sofa.
    public var keepTVSightline: Bool

    public init(
        deskNearWindow: Bool = false,
        openCirculation: Bool = false,
        quietSleeping: Bool = false,
        keepTVSightline: Bool = true
    ) {
        self.deskNearWindow = deskNearWindow
        self.openCirculation = openCirculation
        self.quietSleeping = quietSleeping
        self.keepTVSightline = keepTVSightline
    }

    enum CodingKeys: String, CodingKey {
        case deskNearWindow, openCirculation, quietSleeping, keepTVSightline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deskNearWindow = (try? container.decode(Bool.self, forKey: .deskNearWindow)) ?? false
        self.openCirculation = (try? container.decode(Bool.self, forKey: .openCirculation)) ?? false
        self.quietSleeping = (try? container.decode(Bool.self, forKey: .quietSleeping)) ?? false
        self.keepTVSightline = (try? container.decode(Bool.self, forKey: .keepTVSightline)) ?? true
    }

    /// Union of two constraint sets (any request wins).
    public func merged(with other: LayoutConstraints) -> LayoutConstraints {
        LayoutConstraints(
            deskNearWindow: deskNearWindow || other.deskNearWindow,
            openCirculation: openCirculation || other.openCirculation,
            quietSleeping: quietSleeping || other.quietSleeping,
            keepTVSightline: keepTVSightline || other.keepTVSightline
        )
    }
}

/// Keyword parser shared by the rulebook path, the Foundation Model backstop and the tools.
/// Known limit: no negation handling ("I don't want it spacious" reads as spacious).
public struct UserConstraintParser: Sendable {
    public static let daylightTriggers = ["window", "daylight", "natural light", "sunlight", "sunny", "bright", "glare"]
    public static let spaceTriggers = ["spacious", "more space", "cramped", "move around", "walk", "flow", "open space", "room to move", "crowded"]
    public static let mediaTriggers = ["tv", "television", "sofa", "watch", "sightline", "couch", "lounge"]
    public static let cozyTriggers = ["cozy", "quiet", "sleep", "rest", "sanctuary", "peaceful", "retreat", "privacy", "private"]

    public static func parse(_ text: String) -> LayoutConstraints {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return LayoutConstraints() }
        return LayoutConstraints(
            deskNearWindow: daylightTriggers.contains { lower.contains($0) },
            openCirculation: spaceTriggers.contains { lower.contains($0) },
            quietSleeping: cozyTriggers.contains { lower.contains($0) },
            keepTVSightline: true
        )
    }
}
