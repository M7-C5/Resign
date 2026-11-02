//
//  SpatialTools.swift
//  Resign
//
//  Foundation Model spatial tools allowing Apple Intelligence to inspect room geometry,
//  register user constraints, and preview candidate layouts with real validation.
//

import Foundation
import FoundationModels

@MainActor
public final class SpatialToolContext {
    public let room: Room
    public let layout: Layout
    public var pinnedItemIDs: [UUID] = []
    public var constraints: LayoutConstraints = LayoutConstraints()
    public var toolCallLog: [String] = []

    public init(room: Room, layout: Layout) {
        self.room = room
        self.layout = layout
    }

    public static func makeTools(context: SpatialToolContext) -> [any Tool] {
        [
            MeasureClearanceTool(context: context),
            RegisterUserConstraintTool(context: context),
            PreviewVariantTool(context: context)
        ]
    }

    public func findItem(matching query: String) -> Furniture? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        let active = layout.furnitures.filter { !$0.isArchived }

        // Exact name or category match
        if let exact = active.first(where: { $0.name.lowercased() == q || $0.category.lowercased() == q }) {
            return exact
        }
        // Substring match
        return active.first(where: {
            $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q) ||
            q.contains($0.name.lowercased()) || q.contains($0.category.lowercased())
        })
    }

    public func validItemNames() -> [String] {
        layout.furnitures.filter { !$0.isArchived }.map(\.name)
    }

    public func wallDistance(for box: SpatialClearanceEngine.BoundingBox2D, wall: RoomWall) -> Float {
        let halfW = room.width / 2.0
        let halfL = room.length / 2.0
        switch wall {
        case .north: return max(0, box.minZ - (-halfL))
        case .south: return max(0, halfL - box.maxZ)
        case .east: return max(0, halfW - box.maxX)
        case .west: return max(0, box.minX - (-halfW))
        }
    }
}

public struct MeasureClearanceTool: Tool {
    public let name = "measureClearance"
    public let description = "Measure clearance distance between two pieces of furniture or a furniture piece and a wall."

    @Generable
    public struct Arguments: Sendable {
        @Guide(description: "Name or category of first item, e.g. TV or north wall")
        public var itemA: String

        @Guide(description: "Name or category of second item, e.g. sofa or Queen Bed")
        public var itemB: String

        public init(itemA: String, itemB: String) {
            self.itemA = itemA
            self.itemB = itemB
        }
    }

    private let context: SpatialToolContext

    public init(context: SpatialToolContext) {
        self.context = context
    }

    @MainActor
    public func call(arguments: Arguments) async throws -> String {
        let qA = arguments.itemA.trimmingCharacters(in: .whitespacesAndNewlines)
        let qB = arguments.itemB.trimmingCharacters(in: .whitespacesAndNewlines)

        let wallA = parseWall(qA)
        let wallB = parseWall(qB)
        let itemA = context.findItem(matching: qA)
        let itemB = context.findItem(matching: qB)

        let clearance = SpatialClearanceEngine()

        if let itemA, let itemB {
            let boxA = clearance.boundingBox(for: itemA)
            let boxB = clearance.boundingBox(for: itemB)
            let dist = boxA.distance(to: boxB)
            let cm = Int((dist * 100).rounded())
            let result = "Distance between \(itemA.name) and \(itemB.name) is \(cm) cm."
            context.toolCallLog.append(result)
            return result
        }

        if let item = itemA ?? itemB, let wall = wallA ?? wallB {
            let box = clearance.boundingBox(for: item)
            let dist = context.wallDistance(for: box, wall: wall)
            let cm = Int((dist * 100).rounded())
            let wallName = wall.rawValue.capitalized + " Wall"
            let result = "Distance between \(item.name) and \(wallName) is \(cm) cm."
            context.toolCallLog.append(result)
            return result
        }

        // Neither or one is invalid
        let missing = (itemA == nil && wallA == nil) ? qA : qB
        let validNames = context.validItemNames().joined(separator: ", ")
        let errorMsg = "Item '\(missing)' not found. Valid items: \(validNames), or 'north wall', 'south wall', 'east wall', 'west wall'."
        context.toolCallLog.append(errorMsg)
        return errorMsg
    }

    private func parseWall(_ string: String) -> RoomWall? {
        let lower = string.lowercased()
        if lower.contains("north") { return .north }
        if lower.contains("south") { return .south }
        if lower.contains("east") { return .east }
        if lower.contains("west") { return .west }
        return nil
    }
}

public struct RegisterUserConstraintTool: Tool {
    public let name = "registerUserConstraint"
    public let description = "Register a user spatial preference or pin an item in place during layout generation."

    @Generable
    public enum ConstraintKind: String, Sendable {
        case pinItem
        case deskNearWindow
        case openCirculation
        case quietSleeping
    }

    @Generable
    public struct Arguments: Sendable {
        @Guide(description: "Constraint category: pinItem, deskNearWindow, openCirculation, quietSleeping")
        public var kind: ConstraintKind

        @Guide(description: "Target item name if kind is pinItem (e.g. TV or Queen Bed); leave empty for other kinds")
        public var target: String

        public init(kind: ConstraintKind, target: String = "") {
            self.kind = kind
            self.target = target
        }
    }

    private let context: SpatialToolContext

    public init(context: SpatialToolContext) {
        self.context = context
    }

    @MainActor
    public func call(arguments: Arguments) async throws -> String {
        switch arguments.kind {
        case .pinItem:
            guard let item = context.findItem(matching: arguments.target) else {
                let validNames = context.validItemNames().joined(separator: ", ")
                let msg = "Item '\(arguments.target)' not found. Valid items: \(validNames)."
                context.toolCallLog.append(msg)
                return msg
            }
            if !context.pinnedItemIDs.contains(item.id) {
                context.pinnedItemIDs.append(item.id)
            }
            let msg = "Pinned \(item.name) (ID: \(item.id)) in place."
            context.toolCallLog.append(msg)
            return msg

        case .deskNearWindow:
            context.constraints.deskNearWindow = true
            let msg = "Registered constraint: Desk positioned near window."
            context.toolCallLog.append(msg)
            return msg

        case .openCirculation:
            context.constraints.openCirculation = true
            let msg = "Registered constraint: Open circulation and wider walkways."
            context.toolCallLog.append(msg)
            return msg

        case .quietSleeping:
            context.constraints.quietSleeping = true
            let msg = "Registered constraint: Quiet sleeping area away from doors."
            context.toolCallLog.append(msg)
            return msg
        }
    }
}

public struct PreviewVariantTool: Tool {
    public let name = "previewVariant"
    public let description = "Generate and preview a candidate layout variant, returning physical validation metrics and coordinates."

    @Generable
    public struct Arguments: Sendable {
        @Guide(description: "Variant strategy name: circadian, openFlow, or sanctuary")
        public var strategy: String

        public init(strategy: String) {
            self.strategy = strategy
        }
    }

    private let context: SpatialToolContext

    public init(context: SpatialToolContext) {
        self.context = context
    }

    @MainActor
    public func call(arguments: Arguments) async throws -> String {
        let strategy = LayoutOptimizerEngine.Strategy(token: arguments.strategy) ?? .circadian
        let settings = SolverSettings(
            pinnedItemIds: context.pinnedItemIDs,
            constraints: context.constraints
        )

        let layouts = LayoutOptimizerEngine().generateLayouts(
            for: context.room,
            from: context.layout,
            settings: settings
        )

        let chosenLayout = layouts.first(where: { $0.name == strategy.layoutName }) ?? layouts.first ?? context.layout
        let report = LayoutValidationEngine().validate(room: context.room, furnitures: chosenLayout.furnitures)

        var lines: [String] = []
        lines.append("Preview for \(chosenLayout.name):")
        lines.append("overlaps: \(report.overlaps.count)")
        lines.append("out of bounds: \(report.outOfBounds.count)")
        lines.append("critical violations: \(report.criticalViolations.count)")
        lines.append("Positions:")
        for item in chosenLayout.furnitures where !item.isArchived {
            let xCm = Int((item.positionX * 100).rounded())
            let zCm = Int((item.positionZ * 100).rounded())
            lines.append("- \(item.name): x \(xCm) cm, z \(zCm) cm")
        }

        let summary = lines.joined(separator: "\n")
        context.toolCallLog.append(summary)
        return summary
    }
}
