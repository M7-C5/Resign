//
//  SpatialToolsTests.swift
//  ResignTests
//

import Testing
import Foundation
import FoundationModels
@testable import Resign

@Suite("Foundation Model Spatial Tool Tests")
struct SpatialToolsTests {

    @MainActor
    private func makeContext() -> (SpatialToolContext, Room, Layout) {
        let room = RoomRepository.createStandardMockRoom()
        let layout = room.layouts.first!
        return (SpatialToolContext(room: room, layout: layout), room, layout)
    }

    @Test @MainActor func measureClearanceReportsTheEngineNumber() async throws {
        let (context, _, layout) = makeContext()
        let tv = layout.furnitures.first { $0.category == "television" }!
        let sofa = layout.furnitures.first { $0.category == "sofa" }!
        let expectedCm = Int((SpatialClearanceEngine().boundingBox(for: tv).distance(to: SpatialClearanceEngine().boundingBox(for: sofa)) * 100).rounded())

        let output = try await MeasureClearanceTool(context: context)
            .call(arguments: .init(itemA: "TV", itemB: "sofa"))
        #expect(output.contains("\(expectedCm) cm"), "output was: \(output)")
    }

    @Test @MainActor func measureClearanceSupportsWalls() async throws {
        let (context, _, layout) = makeContext()
        let bed = layout.furnitures.first { $0.category == "bed" }!
        let box = SpatialClearanceEngine().boundingBox(for: bed)
        let expectedCm = Int(((box.minZ + 2.1) * 100).rounded())

        let output = try await MeasureClearanceTool(context: context)
            .call(arguments: .init(itemA: "Queen Bed", itemB: "north wall"))
        #expect(output.contains("\(expectedCm) cm"), "output was: \(output)")
    }

    @Test @MainActor func unknownItemsListTheValidNames() async throws {
        let (context, _, _) = makeContext()
        let output = try await MeasureClearanceTool(context: context)
            .call(arguments: .init(itemA: "piano", itemB: "sofa"))
        #expect(output.localizedCaseInsensitiveContains("not found"))
        #expect(output.contains("Queen Bed"), "must list valid names so the model can retry")
    }

    @Test @MainActor func registeringConstraintsIsRecordedForTheSolver() async throws {
        let (context, _, layout) = makeContext()
        let tool = RegisterUserConstraintTool(context: context)

        _ = try await tool.call(arguments: .init(kind: .pinItem, target: "tv"))
        _ = try await tool.call(arguments: .init(kind: .deskNearWindow, target: ""))
        _ = try await tool.call(arguments: .init(kind: .openCirculation, target: ""))

        let tv = layout.furnitures.first { $0.category == "television" }!
        #expect(context.pinnedItemIDs == [tv.id])
        #expect(context.constraints.deskNearWindow)
        #expect(context.constraints.openCirculation)
        #expect(!context.constraints.quietSleeping)
    }

    @Test @MainActor func pinningAnUnknownItemChangesNothing() async throws {
        let (context, _, _) = makeContext()
        let output = try await RegisterUserConstraintTool(context: context)
            .call(arguments: .init(kind: .pinItem, target: "spaceship"))
        #expect(output.localizedCaseInsensitiveContains("not found"))
        #expect(context.pinnedItemIDs.isEmpty)
    }

    @Test @MainActor func previewVariantReturnsAValidatedOutcome() async throws {
        let (context, _, _) = makeContext()
        for strategy in ["circadian", "openFlow", "sanctuary"] {
            let output = try await PreviewVariantTool(context: context)
                .call(arguments: .init(strategy: strategy))
            #expect(output.contains("overlaps: 0"), "\(strategy): \(output)")
            #expect(output.contains("out of bounds: 0"), "\(strategy): \(output)")
            #expect(output.contains("critical violations: 0"), "\(strategy): \(output)")
        }
    }

    @Test @MainActor func previewVariantHonoursRegisteredConstraints() async throws {
        let (context, _, layout) = makeContext()
        _ = try await RegisterUserConstraintTool(context: context).call(arguments: .init(kind: .pinItem, target: "bed"))
        let bed = layout.furnitures.first { $0.category == "bed" }!
        let output = try await PreviewVariantTool(context: context).call(arguments: .init(strategy: "openFlow"))
        #expect(output.contains("Queen Bed"), "\(output)")
        #expect(output.contains("x \(Int((bed.positionX * 100).rounded())) cm"), "pinned bed must keep its position: \(output)")
    }

    @Test @MainActor func toolsAdvertiseStableNamesAndDescriptions() {
        let (context, _, _) = makeContext()
        let tools: [any Tool] = SpatialToolContext.makeTools(context: context)
        #expect(tools.map { $0.name } == ["measureClearance", "registerUserConstraint", "previewVariant"])
        #expect(tools.allSatisfy { !$0.description.isEmpty })
    }
}
