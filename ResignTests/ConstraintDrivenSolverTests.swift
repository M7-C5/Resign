//
//  ConstraintDrivenSolverTests.swift
//  ResignTests
//

import Testing
import Foundation
@testable import Resign

@Suite("Constraint-Driven Layout Solver Tests")
struct ConstraintDrivenSolverTests {

    let optimizer = LayoutOptimizerEngine()
    let validator = LayoutValidationEngine()
    let clearance = SpatialClearanceEngine()

    // MARK: - Helpers

    @MainActor
    private func solve(
        _ room: Room,
        pinned: (Furniture) -> Bool = { _ in false },
        constraints: LayoutConstraints = LayoutConstraints()
    ) -> (base: Layout, variants: [Layout]) {
        let base = SolverFixtures.baseLayout()
        let settings = SolverSettings(
            pinnedItemIds: base.furnitures.filter(pinned).map(\.id),
            mustHaveItemIds: base.furnitures.map(\.id),
            goalWeights: GoalWeights(spacious: 0.7, balanced: 0.6, reachable: 0.7),
            constraints: constraints
        )
        return (base, optimizer.generateLayouts(for: room, from: base, settings: settings))
    }

    private func item(_ layout: Layout, _ category: String) -> Furniture? {
        layout.furnitures.first { $0.category == category }
    }

    private func isTV(_ f: Furniture) -> Bool { f.category == "television" }

    // MARK: - Hard guarantees in every room

    @Test @MainActor func everyVariantIsCleanInEveryRoomShape() {
        for (name, room) in SolverFixtures.variedRooms {
            for pinTV in [false, true] {
                let (_, variants) = solve(room, pinned: { pinTV && isTV($0) })
                #expect(variants.count == 3, "\(name)")
                for variant in variants {
                    let label = "\(name) / \(variant.name) / pinTV=\(pinTV)"
                    let report = validator.validate(room: room, furnitures: variant.furnitures)
                    if !report.criticalViolations.isEmpty {
                        print("FAIL_LAYOUT: \(label): \(report.criticalViolations.map(\.message))")
                        for f in variant.furnitures {
                            print("  \(f.name) (id: \(f.id)): pos=(\(f.positionX), \(f.positionZ)), yaw=\(f.rotationYaw), size=(\(f.width)x\(f.length))")
                        }
                    }
                    #expect(report.overlaps.isEmpty, "\(label): overlaps \(report.overlaps.map { "\($0.nameA)<>\($0.nameB)" })")
                    #expect(report.outOfBounds.isEmpty, "\(label): out of bounds \(report.outOfBounds.map(\.name))")
                    #expect(report.criticalViolations.isEmpty, "\(label): \(report.criticalViolations.map(\.message))")
                    #expect(report.sightlineBlockers.isEmpty, "\(label): sightline blocked")
                }
            }
        }
    }

    @Test @MainActor func recommendationsAreMeaningfullyDifferent() {
        for (name, room) in SolverFixtures.variedRooms {
            let (_, variants) = solve(room)
            for i in 0..<variants.count {
                for j in (i + 1)..<variants.count {
                    var differing = 0
                    for a in variants[i].furnitures {
                        guard let b = variants[j].furnitures.first(where: { $0.name == a.name }) else { continue }
                        let moved = hypot(a.positionX - b.positionX, a.positionZ - b.positionZ) > 0.5
                        let turned = abs(a.rotationYaw - b.rotationYaw) > 0.1
                        if moved || turned { differing += 1 }
                    }
                    #expect(differing >= 3, "\(name): \(variants[i].name) vs \(variants[j].name) differ in only \(differing) items")
                }
            }
        }
    }

    @Test @MainActor func wallItemsHaveTheirBackAgainstTheNearestWall() {
        for (name, room) in SolverFixtures.variedRooms {
            let (_, variants) = solve(room)
            let halfW = room.width / 2
            let halfL = room.length / 2
            for variant in variants {
                for f in variant.furnitures where ["bed", "desk", "sofa", "closet", "television"].contains(f.category) {
                    let box = clearance.boundingBox(for: f)
                    let toWall: [RoomWall: Float] = [
                        .north: box.minZ + halfL,
                        .south: halfL - box.maxZ,
                        .east: halfW - box.maxX,
                        .west: box.minX + halfW
                    ]
                    let back = FurnitureOrientation.rotate(FurnitureOrientation.nativeBack(forCategory: f.category), yaw: f.rotationYaw)
                    let backWall = RoomWall.allCases.first { abs(back.x - $0.towardWall.x) < 0.01 && abs(back.z - $0.towardWall.z) < 0.01 }!
                    let gap = toWall[backWall] ?? 1.0
                    let label = "\(name) / \(variant.name) / \(f.name)"
                    #expect(gap <= 0.06, "\(label) back is floating \(gap) m off wall \(backWall.rawValue)")
                }
            }
        }
    }

    @Test @MainActor func sofaAndTVFaceEachOther() {
        for (name, room) in SolverFixtures.variedRooms {
            let (_, variants) = solve(room)
            for variant in variants {
                guard let tv = item(variant, "television"), let sofa = item(variant, "sofa") else { continue }
                let toTV = (x: tv.positionX - sofa.positionX, z: tv.positionZ - sofa.positionZ)
                let dist = hypot(toTV.x, toTV.z)
                let sofaFront = FurnitureOrientation.frontDirection(of: sofa)
                let tvFront = FurnitureOrientation.frontDirection(of: tv)
                let sofaDot = (sofaFront.x * toTV.x + sofaFront.z * toTV.z) / dist
                let tvDot = (-tvFront.x * toTV.x - tvFront.z * toTV.z) / dist
                #expect(sofaDot > 0.6, "\(name) / \(variant.name): sofa not facing TV (\(sofaDot))")
                #expect(tvDot > 0.6, "\(name) / \(variant.name): TV not facing sofa (\(tvDot))")
            }
        }
    }

    // MARK: - User intent reaches the solver

    @Test @MainActor func pinnedItemsNeverMove() {
        for (name, room) in SolverFixtures.variedRooms {
            let (base, variants) = solve(room, pinned: { $0.category == "television" || $0.category == "bed" })
            for variant in variants {
                for category in ["television", "bed"] {
                    let original = item(base, category)!
                    let placed = item(variant, category)!
                    #expect(placed.positionX == original.positionX && placed.positionZ == original.positionZ && placed.rotationYaw == original.rotationYaw,
                            "\(name) / \(variant.name): pinned \(category) moved")
                }
            }
        }
    }

    @Test @MainActor func deskNearWindowConstraintAppliesToEveryVariant() {
        for (name, room) in SolverFixtures.variedRooms {
            let window = room.openings.first { $0.type == "window" }!
            let (_, variants) = solve(room, constraints: LayoutConstraints(deskNearWindow: true))
            for variant in variants {
                let desk = item(variant, "desk")!
                let dist = hypot(desk.positionX - window.posX, desk.positionZ - window.posZ)
                #expect(dist < 1.6, "\(name) / \(variant.name): desk is \(dist) m from the window")
            }
        }
    }

    @Test @MainActor func quietSleepingKeepsTheBedFarFromTheDoor() {
        for (name, room) in SolverFixtures.variedRooms {
            let door = room.openings.first { $0.type == "door" }!
            let (_, plain) = solve(room)
            let (_, quiet) = solve(room, constraints: LayoutConstraints(quietSleeping: true))
            for (p, q) in zip(plain, quiet) {
                let bedPlain = item(p, "bed")!
                let bedQuiet = item(q, "bed")!
                let dPlain = hypot(bedPlain.positionX - door.posX, bedPlain.positionZ - door.posZ)
                let dQuiet = hypot(bedQuiet.positionX - door.posX, bedQuiet.positionZ - door.posZ)
                #expect(dQuiet >= dPlain - 0.01, "\(name) / \(q.name): quiet bed (\(dQuiet)) closer to door than default (\(dPlain))")
            }
        }
    }

    @Test @MainActor func openCirculationWidensGapsWhereTheRoomAllows() {
        let room = SolverFixtures.variedRooms.first { $0.name.hasPrefix("large") }!.room
        let (_, variants) = solve(room, constraints: LayoutConstraints(openCirculation: true))
        for variant in variants {
            let items = variant.furnitures
            var minGap: Float = .infinity
            var minPair = ""
            for i in 0..<items.count {
                for j in (i + 1)..<items.count {
                    let pair = Set([items[i].category, items[j].category])
                    if pair == ["desk", "chair"] { continue }
                    let g = clearance.boundingBox(for: items[i]).distance(to: clearance.boundingBox(for: items[j]))
                    if g < minGap {
                        minGap = g
                        minPair = "\(items[i].name) <-> \(items[j].name) (\(items[i].category), \(items[j].category))"
                    }
                }
            }
            #expect(minGap >= 0.895, "\(variant.name): narrowest gap is \(minGap) m between \(minPair) with openCirculation")
        }
    }

    // MARK: - Constraint parsing

    @Test func parserTurnsFreeTextIntoConstraints() {
        let c = UserConstraintParser.parse("desk near the window for natural light, more space to move around, a quiet cozy bed")
        #expect(c.deskNearWindow)
        #expect(c.openCirculation)
        #expect(c.quietSleeping)
        #expect(c.keepTVSightline)

        let none = UserConstraintParser.parse("")
        #expect(!none.deskNearWindow && !none.openCirculation && !none.quietSleeping)
    }

    @Test @MainActor func chipsContributeConstraintsToo() {
        let pref = RoomPreference(selectedKeywords: [.noWorkspace, .feelsCramped, .noPrivacy], freeText: "")
        let c = pref.derivedConstraints
        #expect(c.deskNearWindow)
        #expect(c.openCirculation)
        #expect(c.quietSleeping)
    }

    @Test @MainActor func solverSettingsDecodeWithoutConstraintsKey() throws {
        let json = #"{"pinnedItemIds": [], "mustHaveItemIds": []}"#
        let decoded = try JSONDecoder().decode(SolverSettings.self, from: Data(json.utf8))
        #expect(decoded.constraints == LayoutConstraints())
    }
}
