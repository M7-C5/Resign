//
//  RoomDiagnosticPromptBuilder.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation

public struct RoomDiagnosticPromptBuilder: Sendable {

    public static func mapCategoryToRole(_ category: String) -> String {
        switch category.lowercased() {
        case "bed": return "bed"
        case "desk": return "desk"
        case "chair": return "chair"
        case "closet", "wardrobe", "cupboard": return "wardrobe"
        case "sofa", "couch": return "sofa"
        case "tv", "television", "tv_stand": return "tv"
        default: return category
        }
    }

    public static func createPayload(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        userPreference: String
    ) -> CompactRoomPayload {
        let widthCm = Int((room.width * 100.0).rounded())
        let lengthCm = Int((room.length * 100.0).rounded())
        let heightCm = Int((room.height * 100.0).rounded())

        let compactOpenings = room.openings.map { opening in
            CompactRoomOpening(
                type: opening.type,
                widthCm: Int((opening.width * 100.0).rounded()),
                posXCm: Int((opening.posX * 100.0).rounded()),
                posZCm: Int((opening.posZ * 100.0).rounded())
            )
        }

        let compactItems = layout.furnitures.filter { !$0.isArchived }.map { item in
            let deg = Int((item.rotationYaw * 180.0 / .pi).rounded())
            return CompactRoomItem(
                id: item.id.uuidString,
                name: item.name,
                role: mapCategoryToRole(item.category),
                widthCm: Int((item.width * 100.0).rounded()),
                lengthCm: Int((item.length * 100.0).rounded()),
                heightCm: Int((item.height * 100.0).rounded()),
                posXCm: Int((item.positionX * 100.0).rounded()),
                posZCm: Int((item.positionZ * 100.0).rounded()),
                yawDegrees: deg
            )
        }

        let compactViolations = violations.map { violation in
            CompactViolation(
                ruleId: violation.ruleId,
                itemIds: violation.itemIds.map(\.uuidString),
                measuredCm: Int(violation.measuredClearanceCm.rounded()),
                requiredCm: Int(violation.requiredClearanceCm.rounded()),
                issue: violation.message
            )
        }

        return CompactRoomPayload(
            roomDimensionsCm: [widthCm, lengthCm, heightCm],
            openings: compactOpenings,
            items: compactItems,
            measuredViolations: compactViolations,
            userPreference: userPreference
        )
    }

    public static func buildPrompt(
        room: Room,
        layout: Layout,
        violations: [SpatialViolation],
        userPreference: String
    ) -> String {
        let payload = createPayload(room: room, layout: layout, violations: violations, userPreference: userPreference)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonString: String
        if let data = try? encoder.encode(payload), let str = String(data: data, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = "{}"
        }

        return """
You are an expert architectural ergonomics and interior layout reasoning engine operating under the Panero & Zelnik standard ("Human Dimension & Interior Space").

SYSTEM INSTRUCTIONS & BOUNDARIES:
1. Do NOT calculate 3D coordinates, vectors, or collision geometry. Our deterministic Swift physics engine has already measured exact clearances and identified physical violations.
2. Your responsibility is qualitative reasoning: explain human impacts of detected clashes, cite exact Panero & Zelnik rule IDs (e.g. R1, R2, R3, R4, R5, R6), and formulate solver constraints for our layout optimization engine.
3. Keep room data compact: All dimensions, positions, and clearances are provided in centimeters (cm).
4. Strictly return JSON adhering to the target schema. Every furniture ID cited in insights, pins, or must-haves MUST match one of the exact item IDs provided in the room payload. Never invent new IDs.

INPUT ROOM SITUATION:
Room Dimensions: Width = \(payload.roomDimensionsCm.first ?? 0) cm, Length = \(payload.roomDimensionsCm.count > 1 ? payload.roomDimensionsCm[1] : 0) cm, Height = \(payload.roomDimensionsCm.count > 2 ? payload.roomDimensionsCm[2] : 0) cm.
User Goal / Preference: "\(userPreference)"

DETECTED PHYSICAL VIOLATIONS:
\(violations.isEmpty ? "None detected." : violations.map { "- [\($0.ruleId)] \($0.ruleTitle): measured \(Int($0.measuredClearanceCm.rounded())) cm (required: \(Int($0.requiredClearanceCm.rounded())) cm). \($0.message)" }.joined(separator: "\n"))

ACTIVE ROOM PAYLOAD (JSON):
\(jsonString)

REQUIRED JSON RESPONSE SCHEMA:
{
  "insights": [
    {
      "ruleId": "R1",
      "involvedFurnitureIds": ["<item-uuid>"],
      "explanation": "Plain-English description of human ergonomic friction or clearance bottleneck.",
      "suggestedFix": "Concrete suggestion for repositioning or clearance restoration.",
      "sentiment": "-"
    }
  ],
  "solverSettings": {
    "pinnedItemIds": ["<item-uuid-to-keep-fixed>"],
    "mustHaveItemIds": ["<item-uuid-required-in-room>"],
    "goalWeights": {
      "spacious": 0.8,
      "balanced": 0.5,
      "reachable": 0.7
    }
  }
}
"""
    }
}
