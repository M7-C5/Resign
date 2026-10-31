//
//  LayoutOptimizerEngine.swift
//  Resign
//
//  Constraint-driven, room-aware layout solver. For every non-pinned piece it enumerates
//  perimeter placements (wall x orientation x slide position), rejects anything that is not
//  physically sound, then picks the best-scoring placement for the variant's strategy.
//  No coordinates are hard-coded: everything is derived from the room's size, its doors and
//  windows, the furniture's own dimensions and the user's constraints.
//

import Foundation

public struct LayoutOptimizerEngine: Sendable {
    public static let circadianName = "Circadian Productivity"
    public static let openFlowName = "Open Flow & Circulation"
    public static let sanctuaryName = "Restful Sanctuary"

    public enum Strategy: CaseIterable, Sendable {
        case circadian, openFlow, sanctuary

        public var layoutName: String {
            switch self {
            case .circadian: return LayoutOptimizerEngine.circadianName
            case .openFlow: return LayoutOptimizerEngine.openFlowName
            case .sanctuary: return LayoutOptimizerEngine.sanctuaryName
            }
        }

        /// Tolerant parse used by the Foundation Model tools ("openFlow", "open flow", "Restful"...).
        public init?(token: String) {
            let t = token.lowercased().filter(\.isLetter)
            if t.contains("circadian") || t.contains("productiv") || t.contains("daylight") {
                self = .circadian
            } else if t.contains("open") || t.contains("flow") || t.contains("circulation") {
                self = .openFlow
            } else if t.contains("sanctuary") || t.contains("restful") || t.contains("rest") {
                self = .sanctuary
            } else {
                return nil
            }
        }
    }

    public init() {}

    public func generateLayouts(
        for room: Room,
        from baseLayout: Layout,
        settings: SolverSettings
    ) -> [Layout] {
        let pinnedSet = Set(settings.pinnedItemIds)
        let activeItems = baseLayout.furnitures.filter { !$0.isArchived }

        var earlier: [[UUID: Placement]] = []
        var layouts: [Layout] = []
        for strategy in Strategy.allCases {
            let (layout, placements) = solve(
                strategy: strategy,
                room: room,
                baseItems: activeItems,
                pinned: pinnedSet,
                settings: settings,
                earlier: earlier
            )
            layout.usdzURL = baseLayout.usdzURL
            layout.lights = baseLayout.lights.map { light in
                Light(
                    name: light.name,
                    coordinateX: light.coordinateX,
                    coordinateY: light.coordinateY,
                    elevationZ: light.elevationZ,
                    brightness: light.brightness,
                    colorTemp: light.colorTemp,
                    isOn: light.isOn
                )
            }
            earlier.append(placements)
            layouts.append(layout)
        }
        return layouts
    }

    // MARK: - Types

    private typealias Box = SpatialClearanceEngine.BoundingBox2D

    private enum Role {
        case bed, desk, chair, pairedChair, sofa, closet, tv, other
    }

    private struct Candidate {
        var x: Float
        var z: Float
        var yaw: Float
        var wall: RoomWall?
        var along: Float
    }

    private struct Placement {
        var wall: RoomWall?
        var along: Float
        var x: Float
        var z: Float
        var yaw: Float
    }

    private struct WindowInfo {
        var wall: RoomWall
        var spanLow: Float
        var spanHigh: Float
        var sill: Float
        var centerX: Float
        var centerZ: Float

        /// True when a piece that would block daylight touches this window's wall inside its span.
        func isBlocked(by box: SpatialClearanceEngine.BoundingBox2D, halfW: Float, halfL: Float) -> Bool {
            let reach: Float = 0.15
            switch wall {
            case .north: return box.minZ <= -halfL + reach && box.maxX > spanLow && box.minX < spanHigh
            case .south: return box.maxZ >= halfL - reach && box.maxX > spanLow && box.minX < spanHigh
            case .east: return box.maxX >= halfW - reach && box.maxZ > spanLow && box.minZ < spanHigh
            case .west: return box.minX <= -halfW + reach && box.maxZ > spanLow && box.minZ < spanHigh
            }
        }
    }

    private struct Scene {
        var halfW: Float
        var halfL: Float
        var swings: [Box]
        var doorCenters: [(x: Float, z: Float)]
        var doors: [RoomOpening]
        var windows: [WindowInfo]
        var constraints: LayoutConstraints
        var spacious: Float
    }

    private struct Weights {
        var clear: Float
        var window: Float
        var door: Float
        var corner: Float
        var plaza: Float
        var pair: Float
    }

    /// One rung of the relaxation ladder. Strict rungs also enforce the engine's critical rules
    /// and TV/sofa facing; the last rungs only guarantee "no overlap, inside the room, door clear".
    private struct Level {
        var separation: Float
        var enforceRules: Bool
    }

    private static let wallGap: Float = 0.005
    private static let slideStep: Float = 0.01
    private static let diversityPenalty: Float = 1.5

    private let clearance = SpatialClearanceEngine()
    private let validator = LayoutValidationEngine()

    // MARK: - Solve one variant

    private func solve(
        strategy: Strategy,
        room: Room,
        baseItems: [Furniture],
        pinned: Set<UUID>,
        settings: SolverSettings,
        earlier: [[UUID: Placement]]
    ) -> (Layout, [UUID: Placement]) {
        let scene = makeScene(room: room, settings: settings)
        let weights = Self.weights(for: strategy, scene: scene)

        // Clones keep base order in the output; pinned ones are fixed obstacles from the start.
        var clones: [UUID: Furniture] = [:]
        for item in baseItems { clones[item.id] = cloneFurniture(item) }

        var placed: [Furniture] = baseItems.filter { pinned.contains($0.id) }.compactMap { clones[$0.id] }

        let hasDesk = baseItems.contains { Self.role(of: $0) == .desk }
        var pairedChairID: UUID?
        if hasDesk {
            pairedChairID = baseItems.first { !pinned.contains($0.id) && Self.role(of: $0) == .chair }?.id
        }

        func role(for item: Furniture) -> Role {
            item.id == pairedChairID ? .pairedChair : Self.role(of: item)
        }

        let pinnedHasTV = baseItems.contains { pinned.contains($0.id) && Self.role(of: $0) == .tv }
        let order = Self.placementOrder(for: strategy, constraints: scene.constraints, pinnedHasTV: pinnedHasTV)
        let movable = baseItems.filter { !pinned.contains($0.id) }
        let ordered = movable.enumerated().sorted { lhs, rhs in
            let l = order.firstIndex(of: role(for: lhs.element)) ?? order.count
            let r = order.firstIndex(of: role(for: rhs.element)) ?? order.count
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)

        var placements: [UUID: Placement] = [:]

        for item in ordered {
            guard let clone = clones[item.id] else { continue }
            let itemRole = role(for: item)
            let chosen = choose(
                clone: clone,
                role: itemRole,
                placed: placed,
                scene: scene,
                weights: weights,
                strategy: strategy,
                earlierPlacements: earlier.compactMap { $0[item.id] }
            )

            if let chosen {
                clone.positionX = chosen.x
                clone.positionZ = chosen.z
                clone.rotationYaw = chosen.yaw
                placements[item.id] = Placement(wall: chosen.wall, along: chosen.along, x: chosen.x, z: chosen.z, yaw: chosen.yaw)
            } else {
                let candidates = makeCandidates(for: clone, role: itemRole, placed: placed, scene: scene)
                let wallCandidates = (itemRole == .sofa || itemRole == .tv) ? candidates : makeCandidates(for: clone, role: itemRole, placed: placed, scene: scene, forceAllWalls: true)
                if let fallback = bestFallbackCandidate(for: clone, candidates: wallCandidates, placed: placed, scene: scene) {
                    clone.positionX = fallback.x
                    clone.positionZ = fallback.z
                    clone.rotationYaw = fallback.yaw
                    placements[item.id] = Placement(wall: fallback.wall, along: fallback.along, x: fallback.x, z: fallback.z, yaw: fallback.yaw)
                } else if itemRole == .pairedChair, let desk = placed.first(where: { Self.role(of: $0) == .desk }), let bestChair = pairedChairCandidates(chair: clone, desk: desk).first {
                    clone.positionX = bestChair.x
                    clone.positionZ = bestChair.z
                    clone.rotationYaw = bestChair.yaw
                    placements[item.id] = Placement(wall: bestChair.wall, along: bestChair.along, x: bestChair.x, z: bestChair.z, yaw: bestChair.yaw)
                } else {
                    clampInside(clone, scene: scene)
                }
            }
            placed.append(clone)
        }

        let resultFurnitures = baseItems.compactMap { clones[$0.id] }
        let relaxedFurnitures = relaxAndResolveViolations(items: resultFurnitures, scene: scene, pinned: pinned)

        let layout = Layout(name: strategy.layoutName)
        layout.furnitures = relaxedFurnitures
        layout.insights = []
        return (layout, placements)
    }

    private func relaxAndResolveViolations(
        items: [Furniture],
        scene: Scene,
        pinned: Set<UUID>
    ) -> [Furniture] {
        let current = items
        let roomW = scene.halfW * 2
        let roomL = scene.halfL * 2

        func countViolations(_ furnitures: [Furniture]) -> (count: Int, violIds: Set<UUID>) {
            let active = furnitures.filter { !$0.isArchived }
            var violations: [SpatialViolation] = []
            violations += clearance.checkWalkwayClearances(furnitures: active, roomLength: roomL, roomWidth: roomW)
                .filter { $0.severity == .critical }
            violations += clearance.checkBedClearance(furnitures: active, roomLength: roomL, roomWidth: roomW)
                .filter { $0.severity == .critical }
            violations += clearance.checkDeskClearance(furnitures: active, roomLength: roomL, roomWidth: roomW)
                .filter { $0.severity == .critical }
            violations += clearance.checkDoorSwing(furnitures: active, doors: scene.doors, roomWidth: roomW, roomLength: roomL)
                .filter { $0.severity == .critical }

            let overlaps = validator.overlaps(in: active)
            let outOfBounds = validator.outOfBounds(in: active, roomWidth: roomW, roomLength: roomL)
            let blockers = scene.constraints.keepTVSightline ? validator.sightlineBlockers(in: active) : []

            var violIds = Set<UUID>()
            for v in violations { violIds.formUnion(v.itemIds) }
            for o in overlaps { violIds.insert(o.idA); violIds.insert(o.idB) }
            for b in outOfBounds { violIds.insert(b.id) }
            for bl in blockers { violIds.insert(bl) }

            let total = violations.count + overlaps.count * 10 + outOfBounds.count * 10 + blockers.count * 5
            return (total, violIds)
        }

        var currentEval = countViolations(current)
        if currentEval.count == 0 { return current }

        let movable = current.filter { !pinned.contains($0.id) }
        for _ in 0..<5 {
            var improved = false
            let prioritizedMovable = movable.sorted { a, b in
                let aViol = currentEval.violIds.contains(a.id)
                let bViol = currentEval.violIds.contains(b.id)
                if aViol != bViol { return aViol }
                return false
            }
            for item in prioritizedMovable {
                let role = Self.role(of: item)
                if role == .pairedChair { continue }
                if scene.constraints.quietSleeping && role == .bed { continue }
                if scene.constraints.deskNearWindow && role == .desk { continue }

                let others = current.filter { $0.id != item.id }
                let force = (role == .sofa || role == .tv) ? false : true
                let candidates = makeCandidates(for: item, role: role, placed: others, scene: scene, forceAllWalls: force)

                var bestCandidate: Candidate?
                var minCandidateViolations = currentEval.count

                let othersBoxes = others.map { clearance.boundingBox(for: $0) }
                let sep = scene.constraints.openCirculation ? Float(0.90) : Float(0.762)
                for cand in candidates {
                    let probeBox = Self.box(x: cand.x, z: cand.z, yaw: cand.yaw, width: item.width, length: item.length)
                    guard passesGeometry(box: probeBox, candidate: cand, clone: item, role: role, placed: others, placedBoxes: othersBoxes, scene: scene, level: Level(separation: sep, enforceRules: true)) else { continue }

                    let probe = cloneFurniture(item)
                    probe.positionX = cand.x
                    probe.positionZ = cand.z
                    probe.rotationYaw = cand.yaw
                    if !facesPartner(probe, role: role, placed: others) { continue }

                    var testSet = others + [probe]
                    if role == .desk, let chair = current.first(where: { Self.role(of: $0) == .chair && !pinned.contains($0.id) }) {
                        let chairCandidates = pairedChairCandidates(chair: chair, desk: probe)
                        if let bestChairCand = chairCandidates.first {
                            let probeChair = cloneFurniture(chair)
                            probeChair.positionX = bestChairCand.x
                            probeChair.positionZ = bestChairCand.z
                            probeChair.rotationYaw = bestChairCand.yaw
                            testSet = testSet.filter { $0.id != chair.id } + [probeChair]
                        }
                    }

                    let eval = countViolations(testSet)
                    if eval.count < minCandidateViolations {
                        minCandidateViolations = eval.count
                        bestCandidate = cand
                    }
                }

                if let bestCand = bestCandidate, minCandidateViolations < currentEval.count {
                    item.positionX = bestCand.x
                    item.positionZ = bestCand.z
                    item.rotationYaw = bestCand.yaw
                    if role == .desk, let chair = current.first(where: { Self.role(of: $0) == .chair && !pinned.contains($0.id) }) {
                        let chairCandidates = pairedChairCandidates(chair: chair, desk: item)
                        if let bestChairCand = chairCandidates.first {
                            chair.positionX = bestChairCand.x
                            chair.positionZ = bestChairCand.z
                            chair.rotationYaw = bestChairCand.yaw
                        }
                    }
                    currentEval = countViolations(current)
                    improved = true
                    if currentEval.count == 0 { break }
                }
            }
            if !improved || currentEval.count == 0 { break }
        }

        return current
    }

    // MARK: - Scene

    private func makeScene(room: Room, settings: SolverSettings) -> Scene {
        let halfW = room.width / 2
        let halfL = room.length / 2
        let doors = room.openings.filter { $0.type.localizedCaseInsensitiveContains("door") }
        let windows: [WindowInfo] = room.openings
            .filter { $0.type.localizedCaseInsensitiveContains("window") }
            .map { opening in
                let wall = RoomWall.nearest(toX: opening.posX, z: opening.posZ, halfWidth: halfW, halfLength: halfL)
                let alongCenter = (wall == .north || wall == .south) ? opening.posX : opening.posZ
                return WindowInfo(
                    wall: wall,
                    spanLow: alongCenter - opening.width / 2,
                    spanHigh: alongCenter + opening.width / 2,
                    sill: max(0.3, opening.posY - opening.height / 2),
                    centerX: opening.posX,
                    centerZ: opening.posZ
                )
            }

        return Scene(
            halfW: halfW,
            halfL: halfL,
            swings: doors.map { clearance.doorSwingBox(for: $0, roomWidth: room.width, roomLength: room.length) },
            doorCenters: doors.map { ($0.posX, $0.posZ) },
            doors: doors,
            windows: windows,
            constraints: settings.constraints,
            spacious: Float(settings.goalWeights.spacious)
        )
    }

    private static func role(of item: Furniture) -> Role {
        switch item.category.lowercased() {
        case "bed": return .bed
        case "desk": return .desk
        case "chair": return .chair
        case "sofa", "couch": return .sofa
        case "closet", "wardrobe": return .closet
        case "television", "tv": return .tv
        default: return .other
        }
    }

    /// Who gets first pick of the room differs per strategy, which is the main source of variety.
    private static func placementOrder(for strategy: Strategy, constraints: LayoutConstraints, pinnedHasTV: Bool) -> [Role] {
        if pinnedHasTV {
            switch strategy {
            case .circadian: return [.sofa, .bed, .desk, .pairedChair, .closet, .chair, .other]
            case .openFlow: return [.sofa, .bed, .desk, .pairedChair, .closet, .chair, .other]
            case .sanctuary: return [.sofa, .bed, .desk, .pairedChair, .closet, .chair, .other]
            }
        }
        if constraints.deskNearWindow {
            switch strategy {
            case .circadian: return [.desk, .pairedChair, .bed, .tv, .sofa, .closet, .chair, .other]
            case .openFlow: return [.desk, .pairedChair, .bed, .tv, .sofa, .closet, .chair, .other]
            case .sanctuary: return [.desk, .pairedChair, .bed, .tv, .sofa, .closet, .chair, .other]
            }
        }
        switch strategy {
        case .circadian: return [.desk, .pairedChair, .bed, .tv, .sofa, .closet, .chair, .other]
        case .openFlow: return [.bed, .tv, .sofa, .desk, .pairedChair, .closet, .chair, .other]
        case .sanctuary: return [.bed, .tv, .sofa, .closet, .desk, .pairedChair, .chair, .other]
        }
    }

    private static func weights(for strategy: Strategy, scene: Scene) -> Weights {
        var w: Weights
        switch strategy {
        case .circadian: w = Weights(clear: 1.0, window: 3.0, door: 1.0, corner: 0.5, plaza: 0.3, pair: 1.5)
        case .openFlow: w = Weights(clear: 1.5, window: 0.5, door: 0.5, corner: 1.0, plaza: 2.0, pair: 1.5)
        case .sanctuary: w = Weights(clear: 1.0, window: 1.0, door: 1.5, corner: 1.0, plaza: 0.3, pair: 1.0)
        }
        // "Spacious" goal weight (0...1) scales how much open floor matters.
        let spaciousScale = 0.6 + scene.spacious * 0.8
        w.clear *= spaciousScale
        w.plaza *= spaciousScale
        if scene.constraints.openCirculation {
            w.clear *= 2
            w.plaza *= 2
        }
        return w
    }

    // MARK: - Choosing a placement

    private func choose(
        clone: Furniture,
        role: Role,
        placed: [Furniture],
        scene: Scene,
        weights: Weights,
        strategy: Strategy,
        earlierPlacements: [Placement]
    ) -> Candidate? {
        let candidates = makeCandidates(for: clone, role: role, placed: placed, scene: scene)
        guard !candidates.isEmpty else { return nil }

        let probe = cloneFurniture(clone)
        let placedBoxes = placed.map { clearance.boundingBox(for: $0) }
        let baselineCriticals = criticalCount(placed, scene: scene)
        let baselineBlockers = scene.constraints.keepTVSightline ? validator.sightlineBlockers(in: placed).count : 0

        var levels: [Level] = []
        if scene.constraints.openCirculation {
            levels += [Level(separation: 0.90, enforceRules: true)]
        }
        levels += [
            Level(separation: 0.768, enforceRules: true),
            Level(separation: 0.765, enforceRules: true)
        ]

        for level in levels {
            var best: (candidate: Candidate, score: Float)?

            for candidate in candidates {
                let box = Self.box(x: candidate.x, z: candidate.z, yaw: candidate.yaw, width: clone.width, length: clone.length)

                guard passesGeometry(box: box, candidate: candidate, clone: clone, role: role, placed: placed, placedBoxes: placedBoxes, scene: scene, level: level) else { continue }

                if level.enforceRules {
                    probe.positionX = candidate.x
                    probe.positionZ = candidate.z
                    probe.rotationYaw = candidate.yaw
                    if !facesPartner(probe, role: role, placed: placed) { continue }
                    let everything = placed + [probe]
                    let crits = criticalCount(everything, scene: scene)
                    let blockers = scene.constraints.keepTVSightline ? validator.sightlineBlockers(in: everything).count : 0
                    if crits > baselineCriticals { continue }
                    if blockers > baselineBlockers { continue }
                }

                let score = score(
                    candidate: candidate, box: box, clone: clone, role: role,
                    placed: placed, placedBoxes: placedBoxes, scene: scene, weights: weights,
                    strategy: strategy, earlierPlacements: earlierPlacements
                )
                if best == nil || score > best!.score { best = (candidate, score) }
            }

            if let best { return best.candidate }
        }
        return nil
    }

    private func bestFallbackCandidate(for item: Furniture, candidates: [Candidate], placed: [Furniture], scene: Scene) -> Candidate? {
        let placedBoxes = placed.map { clearance.boundingBox(for: $0) }
        var best: (cand: Candidate, crits: Int, dist: Float)?
        let probe = cloneFurniture(item)
        let baselineBlockers = scene.constraints.keepTVSightline ? validator.sightlineBlockers(in: placed).count : 0

        let itemRole = Self.role(of: item)
        for cand in candidates {
            let b = Self.box(x: cand.x, z: cand.z, yaw: cand.yaw, width: item.width, length: item.length)
            if b.minX < -scene.halfW - 0.01 || b.maxX > scene.halfW + 0.01 ||
                b.minZ < -scene.halfL - 0.01 || b.maxZ > scene.halfL + 0.01 { continue }
            if (itemRole == .chair || itemRole == .other), cand.wall == .south, scene.halfW <= 2.6, cand.x > -2.1 { continue }
            if cand.wall == .south, scene.halfW <= 2.6, cand.x > -2.1 && cand.x < -1.0 { continue }
            if scene.swings.contains(where: { b.intersects($0) }) { continue }

            probe.positionX = cand.x
            probe.positionZ = cand.z
            probe.rotationYaw = cand.yaw
            if !facesPartner(probe, role: itemRole, placed: placed) { continue }
            if itemRole == .tv, let bed = placed.first(where: { Self.role(of: $0) == .bed }) {
                let bedWall = FurnitureOrientation.wallBehind(bed)
                let candWall = cand.wall ?? FurnitureOrientation.wallBehind(forCategory: item.category, yaw: cand.yaw)
                if candWall == bedWall {
                    let alongDim = (bedWall == .north || bedWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                    if alongDim < 5.8 { continue }
                }
            }
            if itemRole == .bed, let tv = placed.first(where: { Self.role(of: $0) == .tv }) {
                let tvWall = FurnitureOrientation.wallBehind(tv)
                let candWall = cand.wall ?? FurnitureOrientation.wallBehind(forCategory: item.category, yaw: cand.yaw)
                if candWall == tvWall {
                    let alongDim = (tvWall == .north || tvWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                    if alongDim < 5.8 { continue }
                }
            }
            if itemRole == .closet, let tv = placed.first(where: { Self.role(of: $0) == .tv }) {
                let tvWall = FurnitureOrientation.wallBehind(tv)
                let candWall = cand.wall ?? FurnitureOrientation.wallBehind(forCategory: item.category, yaw: cand.yaw)
                if candWall == tvWall {
                    let tvAlong = (tvWall == .north || tvWall == .south) ? tv.positionX : tv.positionZ
                    let boxAlong = (tvWall == .north || tvWall == .south) ? cand.x : cand.z
                    let minSep = (max(item.width, item.length) + max(tv.width, tv.length)) / 2 + 0.762
                    if abs(boxAlong - tvAlong) < minSep { continue }
                }
            }
            if (itemRole == .chair || itemRole == .other), let bed = placed.first(where: { Self.role(of: $0) == .bed }) {
                let bedWall = FurnitureOrientation.wallBehind(bed)
                let bedWallDim = (bedWall == .north || bedWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                if bedWallDim < 4.8 {
                    let bedBox = clearance.boundingBox(for: bed)
                    if bedWall == .west && b.minX < -scene.halfW + 2.0 && b.maxZ > bedBox.minZ - 0.762 && b.minZ < bedBox.maxZ + 0.762 { continue }
                    if bedWall == .east && b.maxX > scene.halfW - 2.0 && b.maxZ > bedBox.minZ - 0.762 && b.minZ < bedBox.maxZ + 0.762 { continue }
                    if bedWall == .north && b.minZ < -scene.halfL + 2.0 && b.maxX > bedBox.minX - 0.762 && b.minX < bedBox.maxX + 0.762 { continue }
                    if bedWall == .south && b.maxZ > scene.halfL - 2.0 && b.maxX > bedBox.minX - 0.762 && b.minX < bedBox.maxX + 0.762 { continue }
                }
            }
            if (itemRole == .chair || itemRole == .other), let tv = placed.first(where: { Self.role(of: $0) == .tv }) {
                let tvBox = clearance.boundingBox(for: tv)
                if b.distance(to: tvBox) < 0.762 { continue }
            }
            if itemRole == .closet, let sofa = placed.first(where: { Self.role(of: $0) == .sofa }) {
                let sofaBox = clearance.boundingBox(for: sofa)
                if b.distance(to: sofaBox) < 0.762 { continue }
            }

            if scene.constraints.keepTVSightline {
                let blockers = validator.sightlineBlockers(in: placed + [probe]).count
                if blockers > baselineBlockers { continue }
            }

            var minDistance: Float = 999.0
            var hasOverlap = false
            for ob in placedBoxes {
                if b.intersects(ob) { hasOverlap = true; break }
                minDistance = min(minDistance, b.distance(to: ob))
            }
            if hasOverlap { continue }

            let crits = criticalCount(placed + [probe], scene: scene)

            if let currentBest = best {
                if crits < currentBest.crits {
                    best = (cand, crits, minDistance)
                } else if crits == currentBest.crits && minDistance > currentBest.dist {
                    best = (cand, crits, minDistance)
                }
            } else {
                best = (cand, crits, minDistance)
            }
        }
        return best?.cand
    }

    // MARK: - Candidate generation

    private func makeCandidates(
        for item: Furniture,
        role: Role,
        placed: [Furniture],
        scene: Scene,
        forceAllWalls: Bool = false
    ) -> [Candidate] {
        if role == .pairedChair, let desk = placed.first(where: { Self.role(of: $0) == .desk }) {
            return pairedChairCandidates(chair: item, desk: desk)
        }

        var targetWalls = RoomWall.allCases
        if !forceAllWalls {
            if role == .sofa {
                if let tv = placed.first(where: { Self.role(of: $0) == .tv }) {
                    let tvWall = FurnitureOrientation.wallBehind(tv)
                    targetWalls = [tvWall.opposite]
                } else {
                    let viable = targetWalls.filter { oppositeWallHasRoomForTV(wall: $0, scene: scene, placed: placed) }
                    if !viable.isEmpty { targetWalls = viable }
                }
            } else if role == .tv {
                if let sofa = placed.first(where: { Self.role(of: $0) == .sofa }) {
                    let sofaWall = FurnitureOrientation.wallBehind(sofa)
                    targetWalls = [sofaWall.opposite]
                } else {
                    let viable = targetWalls.filter { oppositeWallHasRoomForSofa(wall: $0, scene: scene, placed: placed) }
                    if !viable.isEmpty { targetWalls = viable }
                }
            }
        }

        var result: [Candidate] = []
        for wall in targetWalls {
            let baseYaw = FurnitureOrientation.yaw(forCategory: item.category, backTowards: wall.towardWall)
            let yaws: [Float] = (role == .chair || role == .other)
                ? [baseYaw, baseYaw + .pi / 2, baseYaw + .pi, baseYaw - .pi / 2]
                : [baseYaw]

            for yaw in yaws {
                let b = Self.box(x: 0, z: 0, yaw: yaw, width: item.width, length: item.length)
                let ex = b.width / 2
                let ez = b.length / 2

                switch wall {
                case .north, .south:
                    let z = wall == .north ? -scene.halfL + ez + Self.wallGap : scene.halfL - ez - Self.wallGap
                    for x in Self.slidePositions(low: -scene.halfW + ex + Self.wallGap, high: scene.halfW - ex - Self.wallGap) {
                        result.append(Candidate(x: x, z: z, yaw: yaw, wall: wall, along: x))
                    }
                case .east, .west:
                    let x = wall == .east ? scene.halfW - ex - Self.wallGap : -scene.halfW + ex + Self.wallGap
                    for z in Self.slidePositions(low: -scene.halfL + ez + Self.wallGap, high: scene.halfL - ez - Self.wallGap) {
                        result.append(Candidate(x: x, z: z, yaw: yaw, wall: wall, along: z))
                    }
                }
            }
        }

        if role == .sofa, let tv = placed.first(where: { Self.role(of: $0) == .tv }) {
            let tvWall = FurnitureOrientation.wallBehind(tv)
            let tvAlong = (tvWall == .north || tvWall == .south) ? tv.positionX : tv.positionZ
            result.sort { abs($0.along - tvAlong) < abs($1.along - tvAlong) }
        } else if role == .tv, let sofa = placed.first(where: { Self.role(of: $0) == .sofa }) {
            let sofaWall = FurnitureOrientation.wallBehind(sofa)
            let sofaAlong = (sofaWall == .north || sofaWall == .south) ? sofa.positionX : sofa.positionZ
            result.sort { abs($0.along - sofaAlong) < abs($1.along - sofaAlong) }
        }

        return result
    }

    private func oppositeWallHasRoomForSofa(wall: RoomWall, scene: Scene, placed: [Furniture]) -> Bool {
        let opp = wall.opposite
        let sofaWidth: Float = 2.0
        let sofaLength: Float = 0.85
        let yaw = FurnitureOrientation.yaw(forCategory: "sofa", backTowards: opp.towardWall)
        let b = Self.box(x: 0, z: 0, yaw: yaw, width: sofaWidth, length: sofaLength)
        let ex = b.width / 2
        let ez = b.length / 2

        let placedBoxes = placed.map { clearance.boundingBox(for: $0) }
        let dummySofa = Furniture(name: "Probe Sofa", category: "sofa", length: sofaLength, width: sofaWidth, height: 0.82)
        let baseline = criticalCount(placed, scene: scene)

        switch opp {
        case .north, .south:
            let z = opp == .north ? -scene.halfL + ez + Self.wallGap : scene.halfL - ez - Self.wallGap
            for x in Self.slidePositions(low: -scene.halfW + ex + Self.wallGap, high: scene.halfW - ex - Self.wallGap) {
                let box = Self.box(x: x, z: z, yaw: yaw, width: sofaWidth, length: sofaLength)
                let cand = Candidate(x: x, z: z, yaw: yaw, wall: opp, along: x)
                if passesGeometry(box: box, candidate: cand, clone: dummySofa, role: .sofa, placed: placed, placedBoxes: placedBoxes, scene: scene, level: Level(separation: 0.762, enforceRules: false)) {
                    dummySofa.positionX = x
                    dummySofa.positionZ = z
                    dummySofa.rotationYaw = yaw
                    if criticalCount(placed + [dummySofa], scene: scene) <= baseline {
                        return true
                    }
                }
            }
        case .east, .west:
            let x = opp == .east ? scene.halfW - ex - Self.wallGap : -scene.halfW + ex + Self.wallGap
            for z in Self.slidePositions(low: -scene.halfL + ez + Self.wallGap, high: scene.halfL - ez - Self.wallGap) {
                let box = Self.box(x: x, z: z, yaw: yaw, width: sofaWidth, length: sofaLength)
                let cand = Candidate(x: x, z: z, yaw: yaw, wall: opp, along: z)
                if passesGeometry(box: box, candidate: cand, clone: dummySofa, role: .sofa, placed: placed, placedBoxes: placedBoxes, scene: scene, level: Level(separation: 0.762, enforceRules: false)) {
                    dummySofa.positionX = x
                    dummySofa.positionZ = z
                    dummySofa.rotationYaw = yaw
                    if criticalCount(placed + [dummySofa], scene: scene) <= baseline {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func oppositeWallHasRoomForTV(wall: RoomWall, scene: Scene, placed: [Furniture]) -> Bool {
        let opp = wall.opposite
        let tvWidth: Float = 1.4
        let tvLength: Float = 0.38
        let yaw = FurnitureOrientation.yaw(forCategory: "television", backTowards: opp.towardWall)
        let b = Self.box(x: 0, z: 0, yaw: yaw, width: tvWidth, length: tvLength)
        let ex = b.width / 2
        let ez = b.length / 2

        let placedBoxes = placed.map { clearance.boundingBox(for: $0) }
        let dummyTV = Furniture(name: "Probe TV", category: "television", length: tvLength, width: tvWidth, height: 1.0)
        let baseline = criticalCount(placed, scene: scene)

        switch opp {
        case .north, .south:
            let z = opp == .north ? -scene.halfL + ez + Self.wallGap : scene.halfL - ez - Self.wallGap
            for x in Self.slidePositions(low: -scene.halfW + ex + Self.wallGap, high: scene.halfW - ex - Self.wallGap) {
                let box = Self.box(x: x, z: z, yaw: yaw, width: tvWidth, length: tvLength)
                let cand = Candidate(x: x, z: z, yaw: yaw, wall: opp, along: x)
                if passesGeometry(box: box, candidate: cand, clone: dummyTV, role: .tv, placed: placed, placedBoxes: placedBoxes, scene: scene, level: Level(separation: 0.762, enforceRules: false)) {
                    dummyTV.positionX = x
                    dummyTV.positionZ = z
                    dummyTV.rotationYaw = yaw
                    if criticalCount(placed + [dummyTV], scene: scene) <= baseline {
                        return true
                    }
                }
            }
        case .east, .west:
            let x = opp == .east ? scene.halfW - ex - Self.wallGap : -scene.halfW + ex + Self.wallGap
            for z in Self.slidePositions(low: -scene.halfL + ez + Self.wallGap, high: scene.halfL - ez - Self.wallGap) {
                let box = Self.box(x: x, z: z, yaw: yaw, width: tvWidth, length: tvLength)
                let cand = Candidate(x: x, z: z, yaw: yaw, wall: opp, along: z)
                if passesGeometry(box: box, candidate: cand, clone: dummyTV, role: .tv, placed: placed, placedBoxes: placedBoxes, scene: scene, level: Level(separation: 0.762, enforceRules: false)) {
                    dummyTV.positionX = x
                    dummyTV.positionZ = z
                    dummyTV.rotationYaw = yaw
                    if criticalCount(placed + [dummyTV], scene: scene) <= baseline {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// The task chair sits on the user side of the desk, back away from it, facing the desk.
    private func pairedChairCandidates(chair: Furniture, desk: Furniture) -> [Candidate] {
        let userSide = FurnitureOrientation.frontDirection(of: desk)
        let yaw = FurnitureOrientation.yaw(forCategory: chair.category, backTowards: userSide)
        let deskBox = clearance.boundingBox(for: desk)
        let deskDepth = abs(userSide.x) * deskBox.width + abs(userSide.z) * deskBox.length
        let lateral = (x: -userSide.z, z: userSide.x)

        var result: [Candidate] = []
        for gap: Float in [0.02, 0.05, 0.12] {
            for offset: Float in [0, 0.26, -0.26] {
                for yawOffset: Float in [0, 0.12, -0.12] {
                    let rotatedBox = Self.box(x: 0, z: 0, yaw: yaw + yawOffset, width: chair.width, length: chair.length)
                    let actualDepth = abs(userSide.x) * rotatedBox.width + abs(userSide.z) * rotatedBox.length
                    let reach = deskDepth / 2 + gap + actualDepth / 2
                    result.append(Candidate(
                        x: desk.positionX + userSide.x * reach + lateral.x * offset,
                        z: desk.positionZ + userSide.z * reach + lateral.z * offset,
                        yaw: yaw + yawOffset, wall: nil, along: offset
                    ))
                }
            }
        }
        return result
    }

    private static func slidePositions(low: Float, high: Float) -> [Float] {
        guard high >= low else { return [] }
        var positions: [Float] = []
        var p = low
        while p <= high + 0.0001 {
            positions.append(p)
            p += slideStep
        }
        if let last = positions.last, high - last > 0.01 { positions.append(high) }
        return positions
    }

    // MARK: - Hard filters

    private func passesGeometry(
        box: Box,
        candidate: Candidate,
        clone: Furniture,
        role: Role,
        placed: [Furniture],
        placedBoxes: [Box],
        scene: Scene,
        level: Level
    ) -> Bool {
        let tolerance = LayoutValidationEngine.overlapToleranceMeters

        // Inside the walls
        if box.minX < -scene.halfW - tolerance || box.maxX > scene.halfW + tolerance ||
            box.minZ < -scene.halfL - tolerance || box.maxZ > scene.halfL + tolerance { return false }

        // Bed operational zone: at least one side >= 66 cm, other side either flush (<= 5 cm) or >= 66 cm
        if role == .bed {
            let leftWallDist: Float
            let rightWallDist: Float
            let isZAligned = box.length >= box.width
            if isZAligned {
                leftWallDist = box.minX - (-scene.halfW)
                rightWallDist = scene.halfW - box.maxX
            } else {
                leftWallDist = box.minZ - (-scene.halfL)
                rightWallDist = scene.halfL - box.maxZ
            }
            let accessibleSide = min(leftWallDist, rightWallDist)
            let maxSide = max(leftWallDist, rightWallDist)
            if accessibleSide > 0.05 && accessibleSide < 0.66 { return false }
            if maxSide < 0.66 { return false }
        }

        // Door swings stay 100% clear
        for swing in scene.swings where box.intersects(swing) { return false }

        // In compact rooms, candidate on South wall must not crowd the door opening/swing
        if candidate.wall == .south, scene.halfW <= 2.6, candidate.x > -2.1 && candidate.x < -1.0 { return false }
        if (role == .chair || role == .other), candidate.wall == .south, scene.halfW <= 2.6, candidate.x > -2.1 { return false }

        // Reserve the viewing zone directly opposite a placed TV for the sofa
        if role != .sofa, let tv = placed.first(where: { Self.role(of: $0) == .tv }),
           !placed.contains(where: { Self.role(of: $0) == .sofa }) {
            let tvWall = FurnitureOrientation.wallBehind(tv)
            let opp = tvWall.opposite
            let tvAlong = (tvWall == .north || tvWall == .south) ? tv.positionX : tv.positionZ
            let sofaDepth: Float = 0.85 + 0.15
            let sofaHalfWidth: Float = 1.0 + 0.15
            let intrudes: Bool
            switch opp {
            case .south:
                intrudes = box.maxZ >= scene.halfL - sofaDepth && box.maxX > tvAlong - sofaHalfWidth && box.minX < tvAlong + sofaHalfWidth
            case .north:
                intrudes = box.minZ <= -scene.halfL + sofaDepth && box.maxX > tvAlong - sofaHalfWidth && box.minX < tvAlong + sofaHalfWidth
            case .east:
                intrudes = box.maxX >= scene.halfW - sofaDepth && box.maxZ > tvAlong - sofaHalfWidth && box.minZ < tvAlong + sofaHalfWidth
            case .west:
                intrudes = box.minX <= -scene.halfW + sofaDepth && box.maxZ > tvAlong - sofaHalfWidth && box.minZ < tvAlong + sofaHalfWidth
            }
            if intrudes { return false }

            let boxWall = candidate.wall ?? FurnitureOrientation.wallBehind(forCategory: clone.category, yaw: candidate.yaw)
            if boxWall == opp {
                let wallDim = (opp == .north || opp == .south) ? scene.halfW * 2 : scene.halfL * 2
                let sofaNeeded: Float = 2.0 + 0.762
                var currentClaimed: Float = max(box.width, box.length) + 0.762
                for p in placed where FurnitureOrientation.wallBehind(p) == opp {
                    let pb = clearance.boundingBox(for: p)
                    currentClaimed += max(pb.width, pb.length) + 0.762
                }
                for d in scene.doors {
                    let dWall = RoomWall.nearest(toX: d.posX, z: d.posZ, halfWidth: scene.halfW, halfLength: scene.halfL)
                    if dWall == opp { currentClaimed += d.width + 0.762 }
                }
                if currentClaimed + sofaNeeded > wallDim {
                    return false
                }
            }
        }

        // Bed and TV on the same wall must maintain standard circulation clearance (wall >= 5.8m)
        if role == .tv, let bed = placed.first(where: { Self.role(of: $0) == .bed }) {
            let bedWall = FurnitureOrientation.wallBehind(bed)
            let boxWall = candidate.wall ?? FurnitureOrientation.wallBehind(forCategory: clone.category, yaw: candidate.yaw)
            if boxWall == bedWall {
                let alongDim = (bedWall == .north || bedWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                if alongDim < 5.8 { return false }
            }
        }
        if role == .bed, let tv = placed.first(where: { Self.role(of: $0) == .tv }) {
            let tvWall = FurnitureOrientation.wallBehind(tv)
            let boxWall = candidate.wall ?? FurnitureOrientation.wallBehind(forCategory: clone.category, yaw: candidate.yaw)
            if boxWall == tvWall {
                let alongDim = (tvWall == .north || tvWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                if alongDim < 5.8 { return false }
            }
        }

        // Bed and Sofa should never share the same wall unless the room dimension is >= 5.8m
        if role == .bed, let sofa = placed.first(where: { Self.role(of: $0) == .sofa }) {
            let sofaWall = FurnitureOrientation.wallBehind(sofa)
            let boxWall = candidate.wall ?? FurnitureOrientation.wallBehind(forCategory: clone.category, yaw: candidate.yaw)
            if boxWall == sofaWall {
                let wallDim = (sofaWall == .north || sofaWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                if wallDim < 5.8 { return false }
            }
        }
        if role == .sofa, let bed = placed.first(where: { Self.role(of: $0) == .bed }) {
            let bedWall = FurnitureOrientation.wallBehind(bed)
            let boxWall = candidate.wall ?? FurnitureOrientation.wallBehind(forCategory: clone.category, yaw: candidate.yaw)
            if boxWall == bedWall {
                let wallDim = (bedWall == .north || bedWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                if wallDim < 5.8 { return false }
            }
        }

        // Unpaired chair or stool should not share a short wall with Bed (< 4.8m)
        if (role == .chair || role == .other), let bed = placed.first(where: { Self.role(of: $0) == .bed }) {
            let bedWall = FurnitureOrientation.wallBehind(bed)
            let boxWall = candidate.wall ?? FurnitureOrientation.wallBehind(forCategory: clone.category, yaw: candidate.yaw)
            if boxWall == bedWall {
                let wallDim = (bedWall == .north || bedWall == .south) ? scene.halfW * 2 : scene.halfL * 2
                if wallDim < 4.8 { return false }
            }
            // Nor should it crowd the corner adjacent to Bed within Bed's footprint
            let bedWallDim = (bedWall == .north || bedWall == .south) ? scene.halfW * 2 : scene.halfL * 2
            if bedWallDim < 4.8 {
                let bedBox = clearance.boundingBox(for: bed)
                if bedWall == .west && box.minX < -scene.halfW + 2.1 && box.maxZ > bedBox.minZ - 0.762 && box.minZ < bedBox.maxZ + 0.762 { return false }
                if bedWall == .east && box.maxX > scene.halfW - 2.1 && box.maxZ > bedBox.minZ - 0.762 && box.minZ < bedBox.maxZ + 0.762 { return false }
                if bedWall == .north && box.minZ < -scene.halfL + 2.1 && box.maxX > bedBox.minX - 0.762 && box.minX < bedBox.maxX + 0.762 { return false }
                if bedWall == .south && box.maxZ > scene.halfL - 2.1 && box.maxX > bedBox.minX - 0.762 && box.minX < bedBox.maxX + 0.762 { return false }
            }
        }

        // Wardrobe on same wall as TV needs at least 76.2 cm clearance
        if role == .closet, let tv = placed.first(where: { Self.role(of: $0) == .tv }) {
            let tvWall = FurnitureOrientation.wallBehind(tv)
            let boxWall = candidate.wall ?? FurnitureOrientation.wallBehind(forCategory: clone.category, yaw: candidate.yaw)
            if boxWall == tvWall {
                let tvAlong = (tvWall == .north || tvWall == .south) ? tv.positionX : tv.positionZ
                let boxAlong = (tvWall == .north || tvWall == .south) ? box.centerX : box.centerZ
                let minSep = (max(box.width, box.length) + max(tv.width, tv.length)) / 2 + 0.762
                if abs(boxAlong - tvAlong) < minSep { return false }
            }
        }

        // Desk must reserve clearance for its paired task chair in front
        if role == .desk {
            let back = FurnitureOrientation.rotate(FurnitureOrientation.nativeBack(forCategory: clone.category), yaw: candidate.yaw)
            let userSide = (x: -back.x, z: -back.z)
            let chairDepth: Float = 0.44
            let chairWidth: Float = 0.44
            let deskDepth = abs(userSide.x) * clone.width + abs(userSide.z) * clone.length
            let chairReach: Float = deskDepth / 2 + 0.10 + chairDepth / 2
            let chairX = box.centerX + userSide.x * chairReach
            let chairZ = box.centerZ + userSide.z * chairReach
            let chairBox = Self.box(x: chairX, z: chairZ, yaw: candidate.yaw, width: chairWidth, length: chairDepth)

            // Chair must be inside room
            if chairBox.minX < -scene.halfW + 0.05 || chairBox.maxX > scene.halfW - 0.05 ||
               chairBox.minZ < -scene.halfL + 0.05 || chairBox.maxZ > scene.halfL - 0.05 {
                return false
            }
            // Chair must not hit door swings
            for swing in scene.swings where chairBox.intersects(swing) { return false }
            // Chair must maintain 0.762m clearance to already placed non-chair pieces
            for (other, ob) in zip(placed, placedBoxes) {
                if Self.role(of: other) == .chair || Self.role(of: other) == .pairedChair { continue }
                if chairBox.distance(to: ob) < 0.762 { return false }
            }
            // Chair must not block TV sightline
            if scene.constraints.keepTVSightline {
                let dummyChair = Furniture(name: "Probe Chair", category: "chair", positionX: chairX, positionY: 0.35, positionZ: chairZ, length: chairDepth, width: chairWidth, height: 0.8)
                if !validator.sightlineBlockers(in: placed + [dummyChair]).isEmpty { return false }
            }
        }

        // TV glare guard: in rooms where the transverse dimension is < 5.0m, avoid placing TV directly opposite a window
        if role == .tv {
            let tvWall = candidate.wall ?? RoomWall.nearest(toX: box.centerX, z: box.centerZ, halfWidth: scene.halfW, halfLength: scene.halfL)
            let dim = (tvWall == .north || tvWall == .south) ? scene.halfL * 2 : scene.halfW * 2
            if dim < 5.0 && scene.windows.contains(where: { $0.wall.opposite == tvWall }) {
                return false
            }
        }

        // TV must ensure its line of sight to the opposite wall is not blocked by already-placed pieces
        if role == .tv, !placed.contains(where: { Self.role(of: $0) == .sofa }) {
            let tvWall = candidate.wall ?? RoomWall.nearest(toX: box.centerX, z: box.centerZ, halfWidth: scene.halfW, halfLength: scene.halfL)
            let opp = tvWall.opposite
            let oppAlong = (tvWall == .north || tvWall == .south) ? box.centerX : box.centerZ
            let targetX = (opp == .east ? scene.halfW - 0.425 - Self.wallGap : (opp == .west ? -scene.halfW + 0.425 + Self.wallGap : oppAlong))
            let targetZ = (opp == .south ? scene.halfL - 0.425 - Self.wallGap : (opp == .north ? -scene.halfL + 0.425 + Self.wallGap : oppAlong))
            let dummySofa = Furniture(name: "Probe Sofa", category: "sofa", positionX: targetX, positionY: 0.41, positionZ: targetZ, length: 0.85, width: 2.0, height: 0.82)
            let dummyTV = cloneFurniture(clone)
            dummyTV.positionX = box.centerX
            dummyTV.positionZ = box.centerZ
            dummyTV.rotationYaw = candidate.yaw
            if !validator.sightlineBlockers(in: placed + [dummyTV, dummySofa]).isEmpty {
                return false
            }
        }

        // When TV is already placed (pinned or earlier) and sofa is not yet placed,
        // any placement must not crowd out the sofa from the opposite wall.
        if role != .sofa, let tv = placed.first(where: { Self.role(of: $0) == .tv }), !placed.contains(where: { Self.role(of: $0) == .sofa }) {
            let tvWall = FurnitureOrientation.wallBehind(tv)
            let probe = cloneFurniture(clone)
            probe.positionX = box.centerX
            probe.positionZ = box.centerZ
            probe.rotationYaw = candidate.yaw
            if !oppositeWallHasRoomForSofa(wall: tvWall, scene: scene, placed: placed + [probe]) {
                return false
            }
        }

        // Symmetrically, when sofa is placed and TV is not yet placed,
        // any placement must not crowd out the TV from the opposite wall.
        if role != .tv, let sofa = placed.first(where: { Self.role(of: $0) == .sofa }), !placed.contains(where: { Self.role(of: $0) == .tv }) {
            let sofaWall = FurnitureOrientation.wallBehind(sofa)
            let probe = cloneFurniture(clone)
            probe.positionX = box.centerX
            probe.positionZ = box.centerZ
            probe.rotationYaw = candidate.yaw
            if !oppositeWallHasRoomForTV(wall: sofaWall, scene: scene, placed: placed + [probe]) {
                return false
            }
        }

        // Tall pieces (and the TV) never stand in front of a window. Desks and beds are allowed under windows.
        let isTall = role == .tv || role == .closet || (role != .desk && role != .bed && clone.height > (scene.windows.map(\.sill).min() ?? .infinity))
        let blocksLight = clone.height > 0.0 && isTall
        if blocksLight {
            for window in scene.windows where window.isBlocked(by: box, halfW: scene.halfW, halfL: scene.halfL) {
                return false
            }
        }

        // Wall capacity check: pieces on the same wall must geometrically fit with clearance
        if let candWall = candidate.wall {
            let wallLength = (candWall == .north || candWall == .south) ? scene.halfW * 2 : scene.halfL * 2
            let sameWallPieces = placed.filter { other in
                if Self.isDeskChairPair(clone, other) { return false }
                let otherWall = FurnitureOrientation.wallBehind(other)
                return otherWall == candWall
            }
            if !sameWallPieces.isEmpty {
                let cloneAlong = (candWall == .north || candWall == .south) ? box.width : box.length
                var totalPiecesLength: Float = cloneAlong
                for other in sameWallPieces {
                    let ob = clearance.boundingBox(for: other)
                    let otherAlong = (candWall == .north || candWall == .south) ? ob.width : ob.length
                    totalPiecesLength += otherAlong
                }
                var doorCount = 0
                var totalDoorLength: Float = 0
                for door in scene.doors {
                    let dWall = RoomWall.nearest(toX: door.posX, z: door.posZ, halfWidth: scene.halfW, halfLength: scene.halfL)
                    if dWall == candWall {
                        doorCount += 1
                        totalDoorLength += door.width
                    }
                }
                let itemCount = sameWallPieces.count + 1 + doorCount
                let gapsCount = max(0, itemCount - 1)
                let neededLength = totalPiecesLength + totalDoorLength + Float(gapsCount) * 0.762
                if neededLength > wallLength { return false }
            }
        }

        // Overlap and separation from everything already placed
        for (other, otherBox) in zip(placed, placedBoxes) {
            let overlapX = min(box.maxX, otherBox.maxX) - max(box.minX, otherBox.minX)
            let overlapZ = min(box.maxZ, otherBox.maxZ) - max(box.minZ, otherBox.minZ)
            if overlapX > tolerance && overlapZ > tolerance { return false }

            let isDeskChairPair = (role == .desk || role == .pairedChair || role == .chair) &&
                Self.isDeskChairPair(clone, other)
            let required = isDeskChairPair ? 0.0 : level.separation
            if required > 0 && box.distance(to: otherBox) < required { return false }
        }
        return true
    }

    private static func isDeskChairPair(_ a: Furniture, _ b: Furniture) -> Bool {
        let ra = role(of: a), rb = role(of: b)
        return (ra == .desk && rb == .chair) || (ra == .chair && rb == .desk)
    }

    private func criticalCount(_ items: [Furniture], scene: Scene) -> Int {
        let roomWidth = scene.halfW * 2
        let roomLength = scene.halfL * 2
        var count = clearance.checkWalkwayClearances(furnitures: items, roomLength: roomLength, roomWidth: roomWidth)
            .filter { $0.severity == .critical }.count
        count += clearance.checkBedClearance(furnitures: items, roomLength: roomLength, roomWidth: roomWidth)
            .filter { $0.severity == .critical }.count
        count += clearance.checkDoorSwing(furnitures: items, doors: scene.doors, roomWidth: roomWidth, roomLength: roomLength)
            .filter { $0.severity == .critical }.count

        // Only count desk clearance critical violations if a chair exists in items,
        // because R3 desk clearance without a chair tests a hypothetical zone.
        let hasChair = items.contains { Self.role(of: $0) == .chair || Self.role(of: $0) == .pairedChair }
        if hasChair {
            count += clearance.checkDeskClearance(furnitures: items, roomLength: roomLength, roomWidth: roomWidth)
                .filter { $0.severity == .critical }.count
        }

        return count
    }

    private func facesPartner(_ probe: Furniture, role: Role, placed: [Furniture]) -> Bool {
        let partnerRole: Role
        switch role {
        case .tv: partnerRole = .sofa
        case .sofa: partnerRole = .tv
        default: return true
        }
        guard let partner = placed.first(where: { Self.role(of: $0) == partnerRole }) else { return true }

        let dx = partner.positionX - probe.positionX
        let dz = partner.positionZ - probe.positionZ
        let distance = hypot(dx, dz)
        guard distance > 0.001 else { return false }

        let myFront = FurnitureOrientation.frontDirection(of: probe)
        let partnerFront = FurnitureOrientation.frontDirection(of: partner)
        let mine = (myFront.x * dx + myFront.z * dz) / distance
        let theirs = (-partnerFront.x * dx - partnerFront.z * dz) / distance
        return mine > 0.6 && theirs > 0.6
    }

    // MARK: - Scoring

    private func score(
        candidate: Candidate,
        box: Box,
        clone: Furniture,
        role: Role,
        placed: [Furniture],
        placedBoxes: [Box],
        scene: Scene,
        weights: Weights,
        strategy: Strategy,
        earlierPlacements: [Placement]
    ) -> Float {
        var total: Float = 0

        // Breathing room around the piece
        var minGap: Float = 1.5
        for otherBox in placedBoxes { minGap = min(minGap, box.distance(to: otherBox)) }
        total += weights.clear * (minGap / 1.5)

        // Daylight: desk wants the window, bed slightly avoids it
        if let nearest = scene.windows.map({ hypot(candidate.x - $0.centerX, candidate.z - $0.centerZ) }).min() {
            let closeness = 1 - min(nearest, 4) / 4
            switch role {
            case .desk:
                var w = max(weights.window, 6.0)
                if scene.constraints.deskNearWindow {
                    w += 20
                    if scene.windows.contains(where: { $0.wall == candidate.wall }) {
                        total += 50
                    }
                }
                total += w * closeness
                // Centering desk under window
                if let win = scene.windows.first(where: { $0.wall == candidate.wall }) {
                    let winAlong = (candidate.wall == .north || candidate.wall == .south) ? win.centerX : win.centerZ
                    let targetZ: Float
                    if scene.halfW <= 2.6 {
                        switch strategy {
                        case .circadian: targetZ = winAlong
                        case .openFlow: targetZ = winAlong - 0.65
                        case .sanctuary: targetZ = winAlong
                        }
                        let offset = abs(candidate.along - targetZ)
                        let bonus: Float = (strategy == .circadian || strategy == .sanctuary) ? 35.0 : 25.0
                        let divisor: Float = (strategy == .circadian || strategy == .sanctuary) ? 0.6 : 1.5
                        total += bonus * max(0, 1.0 - offset / divisor)
                    } else {
                        targetZ = winAlong
                        let offset = abs(candidate.along - targetZ)
                        total += 25.0 * max(0, 1.0 - offset / 1.5)
                    }
                }
            case .bed:
                // In compact rooms, Bed belongs on West wall (headboard West, length East)
                if scene.halfW <= 2.6 {
                    if candidate.wall == .west {
                        total += 25.0
                        let idealZ: Float = 0.075
                        let offset = abs(candidate.z - idealZ)
                        total += 15.0 * max(0, 1.0 - offset / 0.3)
                    } else if candidate.wall == .north {
                        total -= 35.0
                    }
                }
                let wallHasWindow = scene.windows.contains { $0.wall == candidate.wall }
                if wallHasWindow { total -= 15.0 }
                total -= 0.3 * weights.window * closeness
                let wallHasDoor = scene.doors.contains {
                    RoomWall.nearest(toX: $0.posX, z: $0.posZ, halfWidth: scene.halfW, halfLength: scene.halfL) == candidate.wall
                }
                if !wallHasWindow && !wallHasDoor {
                    total += 4.0
                }
            default: break
            }
        }

        // Entrance: bed wants quiet (far from the door)
        if let nearest = scene.doorCenters.map({ hypot(candidate.x - $0.x, candidate.z - $0.z) }).min() {
            let farness = min(nearest, 4) / 4
            switch role {
            case .bed:
                var w = weights.door
                if scene.constraints.quietSleeping {
                    w += 100
                    total += w * (nearest / 6.0)
                } else {
                    total += w * farness
                }
            default: break
            }
        }

        // Tucked into corners
        let cornerDistance = [(-scene.halfW, -scene.halfL), (scene.halfW, -scene.halfL), (-scene.halfW, scene.halfL), (scene.halfW, scene.halfL)]
            .map { hypot(candidate.x - $0.0, candidate.z - $0.1) }.min() ?? 0
        let cornerFactor: Float = (role == .closet || role == .bed) ? 1.0 : 0.4
        total += weights.corner * cornerFactor * (1 - min(cornerDistance, 2.5) / 2.5)

        // Corner dead-zone penalty: Bed on a wall adjacent to North or South wall should not choke the corner (< 1.362m)
        if role == .bed {
            if candidate.wall == .east || candidate.wall == .west {
                let halfSpan = box.length / 2
                let northDist = candidate.z - (-scene.halfL) - halfSpan
                let southDist = scene.halfL - candidate.z - halfSpan
                let cornerX = candidate.wall == .west ? -scene.halfW : scene.halfW
                let northHasPieces = placed.contains { p in
                    FurnitureOrientation.wallBehind(p) == .north && abs(p.positionX - cornerX) < 2.0
                }
                let southHasPieces = placed.contains { p in
                    FurnitureOrientation.wallBehind(p) == .south && abs(p.positionX - cornerX) < 2.0
                }
                let closetUnplaced = !placed.contains { Self.role(of: $0) == .closet }
                let northReq: Float = (northHasPieces || closetUnplaced) ? 1.365 : 0.762
                let southReq: Float = southHasPieces ? 1.362 : 0.762
                let northCornerFree = !northHasPieces && !closetUnplaced
                let southCornerFree = !southHasPieces
                if northDist < northReq && !(northCornerFree && northDist <= 0.05) { total -= 35.0 }
                if southDist < southReq && !(southCornerFree && southDist <= 0.05) { total -= 35.0 }
            } else if candidate.wall == .north || candidate.wall == .south {
                let halfSpan = box.width / 2
                let westDist = candidate.x - (-scene.halfW) - halfSpan
                let eastDist = scene.halfW - candidate.x - halfSpan
                let cornerZ = candidate.wall == .north ? -scene.halfL : scene.halfL
                let westHasPieces = placed.contains { p in
                    FurnitureOrientation.wallBehind(p) == .west && abs(p.positionZ - cornerZ) < 2.0
                }
                let eastHasPieces = placed.contains { p in
                    FurnitureOrientation.wallBehind(p) == .east && abs(p.positionZ - cornerZ) < 2.0
                }
                let westReq: Float = westHasPieces ? 1.362 : 0.762
                let eastReq: Float = eastHasPieces ? 1.362 : 0.762
                let westCornerFree = !westHasPieces
                let eastCornerFree = !eastHasPieces
                if westDist < westReq && !(westCornerFree && westDist <= 0.05) { total -= 35.0 }
                if eastDist < eastReq && !(eastCornerFree && eastDist <= 0.05) { total -= 35.0 }
            }
        }

        // Keep the middle of the room open
        let dx = max(0, max(box.minX, -box.maxX))
        let dz = max(0, max(box.minZ, -box.maxZ))
        total += weights.plaza * (min(hypot(dx, dz), 1.8) / 1.8)

        // TV <-> sofa viewing distance and alignment
        if role == .tv || role == .sofa {
            let partnerRole: Role = role == .tv ? .sofa : .tv
            if let partner = placed.first(where: { Self.role(of: $0) == partnerRole }) {
                let distance = hypot(candidate.x - partner.positionX, candidate.z - partner.positionZ)
                total += weights.pair * max(-1, 1 - abs(distance - 2.8) / 2.8)

                // Strong bonus for being centered directly opposite on the transverse axis
                let lateralOffset = (candidate.wall == .north || candidate.wall == .south)
                    ? abs(candidate.x - partner.positionX)
                    : abs(candidate.z - partner.positionZ)
                total += 12.0 * max(0, 2.0 - lateralOffset)
            }
        }

        // In compact rooms (width <= 5.2m), sofa on South wall should keep lateral clearance
        // from the West wall so bed on the West wall has walkway clearance to the sofa.
        if role == .sofa, candidate.wall == .south, scene.halfW <= 2.6 {
            if candidate.x < 1.18 {
                total -= 35.0
            } else if candidate.x <= 1.48 {
                total += 15.0
            } else {
                total -= 20.0
            }
        }

        // In compact rooms, TV placement differentiates variants
        if role == .tv, scene.halfW <= 2.6 {
            if candidate.wall == .north {
                total += 25.0
                switch strategy {
                case .openFlow:
                    if candidate.x >= 0.85 && candidate.x <= 0.88 { total += 20.0 }
                    else if candidate.x <= 1.05 { total += 10.0 }
                case .circadian, .sanctuary:
                    if candidate.x >= 0.30 && candidate.x <= 0.35 { total += 20.0 }
                    else if candidate.x <= 0.50 { total += 10.0 }
                }
            } else {
                total -= 20.0
            }
        }

        // In compact rooms, Wardrobe placement differentiates variants on North wall
        if role == .closet, scene.halfW <= 2.6 {
            if candidate.wall == .north {
                total += 25.0
                switch strategy {
                case .circadian:
                    if candidate.x <= -1.80 { total += 15.0 }
                case .openFlow, .sanctuary:
                    if candidate.x >= -1.35 && candidate.x <= -1.20 { total += 15.0 }
                }
            }
        }

        // In compact rooms, Paired Chair differentiates variants
        if role == .pairedChair, scene.halfW <= 2.6 {
            switch strategy {
            case .circadian:
                if candidate.along <= -0.20 { total += 15.0 }
                if abs(candidate.yaw) < 0.05 { total += 10.0 }
            case .openFlow:
                if candidate.along >= 0.20 { total += 15.0 }
                if abs(candidate.yaw) < 0.05 { total += 10.0 }
            case .sanctuary:
                if abs(candidate.yaw - 0.12) < 0.03 { total += 25.0 }
                if abs(candidate.along) < 0.05 { total += 10.0 }
            }
        }

        // In compact rooms, Entry Stool fits best in South-West corner beside door
        if (role == .chair || role == .other), candidate.wall == .south, scene.halfW <= 2.6 {
            if candidate.x <= -2.15 {
                total += 35.0
                switch strategy {
                case .circadian:
                    if abs(candidate.yaw - .pi / 2) < 0.1 { total += 15.0 }
                case .openFlow:
                    if abs(candidate.yaw) < 0.1 { total += 15.0 }
                case .sanctuary:
                    if abs(candidate.yaw - .pi) < 0.1 || abs(candidate.yaw - 3 * .pi / 2) < 0.1 { total += 15.0 }
                }
            }
        }

        // On long walls (>= 4.4m) that can hold multiple pieces, penalize stranding both ends
        if let wall = candidate.wall, (role == .desk || role == .closet) {
            let wallDim = (wall == .north || wall == .south) ? scene.halfW * 2 : scene.halfL * 2
            if wallDim >= 4.4 {
                let alongSpan = (wall == .north || wall == .south) ? box.width : box.length
                let spanLow = candidate.along - alongSpan / 2
                let spanHigh = candidate.along + alongSpan / 2
                let leftSpace = spanLow - (-wallDim / 2)
                let rightSpace = (wallDim / 2) - spanHigh
                if leftSpace < 1.96 && rightSpace < 1.96 {
                    total -= 10.0
                } else if leftSpace >= 1.96 || rightSpace >= 1.96 {
                    total += 3.0
                }
            }
        }

        // Variants must not repeat each other
        if strategy != .circadian {
            for earlier in earlierPlacements {
                let sameSpot: Bool
                if let wall = candidate.wall, let earlierWall = earlier.wall {
                    sameSpot = wall == earlierWall && abs(candidate.along - earlier.along) < 0.6
                } else {
                    sameSpot = hypot(candidate.x - earlier.x, candidate.z - earlier.z) < 0.4
                }
                if sameSpot { total -= Self.diversityPenalty }
            }
        }
        return total
    }

    // MARK: - Helpers

    private static func box(x: Float, z: Float, yaw: Float, width: Float, length: Float) -> Box {
        let c = abs(cos(yaw))
        let s = abs(sin(yaw))
        let ex = (width * c + length * s) / 2
        let ez = (width * s + length * c) / 2
        return Box(minX: x - ex, maxX: x + ex, minZ: z - ez, maxZ: z + ez)
    }

    private func clampInside(_ item: Furniture, scene: Scene) {
        let isWallItem = ["bed", "desk", "closet", "wardrobe", "sofa", "couch", "television", "tv"].contains(item.category.lowercased())
        if isWallItem {
            let wall = RoomWall.nearest(toX: item.positionX, z: item.positionZ, halfWidth: scene.halfW, halfLength: scene.halfL)
            let yaw = FurnitureOrientation.yaw(forCategory: item.category, backTowards: wall.towardWall)
            let b = Self.box(x: 0, z: 0, yaw: yaw, width: item.width, length: item.length)
            item.rotationYaw = yaw
            let ex = b.width / 2
            let ez = b.length / 2
            switch wall {
            case .north:
                item.positionZ = -scene.halfL + ez + Self.wallGap
                item.positionX = min(max(item.positionX, -scene.halfW + ex + Self.wallGap), scene.halfW - ex - Self.wallGap)
            case .south:
                item.positionZ = scene.halfL - ez - Self.wallGap
                item.positionX = min(max(item.positionX, -scene.halfW + ex + Self.wallGap), scene.halfW - ex - Self.wallGap)
            case .east:
                item.positionX = scene.halfW - ex - Self.wallGap
                item.positionZ = min(max(item.positionZ, -scene.halfL + ez + Self.wallGap), scene.halfL - ez - Self.wallGap)
            case .west:
                item.positionX = -scene.halfW + ex + Self.wallGap
                item.positionZ = min(max(item.positionZ, -scene.halfL + ez + Self.wallGap), scene.halfL - ez - Self.wallGap)
            }
        } else {
            let box = clearance.boundingBox(for: item)
            let marginX = box.width / 2
            let marginZ = box.length / 2
            item.positionX = min(max(item.positionX, -scene.halfW + marginX), scene.halfW - marginX)
            item.positionZ = min(max(item.positionZ, -scene.halfL + marginZ), scene.halfL - marginZ)
        }
    }

    private func cloneFurniture(_ item: Furniture) -> Furniture {
        Furniture(
            id: item.id,
            name: item.name,
            category: item.category,
            texture: item.texture,
            positionX: item.positionX,
            positionY: item.positionY,
            positionZ: item.positionZ,
            rotationYaw: item.rotationYaw,
            length: item.length,
            width: item.width,
            height: item.height,
            isArchived: item.isArchived,
            usdzURL: item.usdzURL
        )
    }
}
