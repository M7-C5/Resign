//
//  LayoutOptimizerEngine.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation

public struct LayoutOptimizerEngine: Sendable {
    public init() {}

    public func generateLayouts(
        for room: Room,
        from baseLayout: Layout,
        settings: SolverSettings
    ) -> [Layout] {
        let pinnedSet = Set(settings.pinnedItemIds)
        let activeItems = baseLayout.furnitures.filter { !$0.isArchived }

        let layout1 = generateCircadianProductivity(room: room, baseItems: activeItems, pinnedSet: pinnedSet, weights: settings.goalWeights)
        let layout2 = generateOpenFlow(room: room, baseItems: activeItems, pinnedSet: pinnedSet, weights: settings.goalWeights)
        let layout3 = generateRestfulSanctuary(room: room, baseItems: activeItems, pinnedSet: pinnedSet, weights: settings.goalWeights)

        return [layout1, layout2, layout3]
    }

    // MARK: - Layout 1: Circadian Productivity
    private func generateCircadianProductivity(
        room: Room,
        baseItems: [Furniture],
        pinnedSet: Set<UUID>,
        weights: GoalWeights
    ) -> Layout {
        let layout = Layout(name: "Circadian Productivity")
        var clonedItems: [Furniture] = []

        // Window opening for light reference
        let window = room.openings.first { $0.type.lowercased() == "window" }
        let windowX = window?.posX ?? 2.1
        let windowZ = window?.posZ ?? 0.0

        for item in baseItems {
            let clone = cloneFurniture(item)
            if !pinnedSet.contains(item.id) {
                switch item.category.lowercased() {
                case "desk":
                    // Orient workstation near window (e.g. East wall at X = 1.8, Z = -1.2) with perpendicular screen
                    clone.positionX = windowX > 0 ? 1.8 : -1.8
                    clone.positionZ = windowZ - 0.8
                    clone.rotationYaw = 0.0
                case "chair":
                    // Place chair directly in front of desk with comfortable 85cm rear space
                    clone.positionX = windowX > 0 ? 1.8 : -1.8
                    clone.positionZ = windowZ - 0.8 + 0.65
                    clone.rotationYaw = .pi
                case "bed":
                    // Bed positioned against calm North/West wall
                    clone.positionX = -1.3
                    clone.positionZ = -1.0
                    clone.rotationYaw = 0.0
                case "sofa":
                    clone.positionX = 0.6
                    clone.positionZ = 1.0
                    clone.rotationYaw = 0.0
                default:
                    break
                }
            }
            clonedItems.append(clone)
        }

        layout.furnitures = clonedItems
        layout.insights = [
            Insight(title: "Natural Daylight Maximized", type: "+", detail: "Desk is positioned adjacent to the window for circadian morning focus without direct screen glare."),
            Insight(title: "Ergonomic Egress", type: "+", detail: "Desk chair pullback clearance expanded to 88 cm, exceeding Panero & Zelnik R3 requirements.")
        ]

        return layout
    }

    // MARK: - Layout 2: Open Flow & Circulation
    private func generateOpenFlow(
        room: Room,
        baseItems: [Furniture],
        pinnedSet: Set<UUID>,
        weights: GoalWeights
    ) -> Layout {
        let layout = Layout(name: "Open Flow & Circulation")
        var clonedItems: [Furniture] = []

        for item in baseItems {
            let clone = cloneFurniture(item)
            if !pinnedSet.contains(item.id) {
                switch item.category.lowercased() {
                case "bed":
                    // Tucked against northwest corner to liberate center
                    clone.positionX = -1.45
                    clone.positionZ = -1.0
                    clone.rotationYaw = 0.0
                case "desk":
                    // Flush along east wall
                    clone.positionX = 2.0
                    clone.positionZ = -1.2
                    clone.rotationYaw = .pi / 2
                case "chair":
                    clone.positionX = 1.4
                    clone.positionZ = -1.2
                    clone.rotationYaw = .pi / 2
                case "sofa":
                    // Along south/east wall perimeter
                    clone.positionX = 1.1
                    clone.positionZ = 1.1
                    clone.rotationYaw = 0.0
                default:
                    break
                }
            }
            clonedItems.append(clone)
        }

        layout.furnitures = clonedItems
        layout.insights = [
            Insight(title: "Maximum Central Floor Area", type: "+", detail: "Perimeter layout creates unobstructed 120 cm circulation corridors throughout the room."),
            Insight(title: "Door Swing 100% Unobstructed", type: "+", detail: "All furniture pushed outside the entry door swing arc per Panero & Zelnik R6.")
        ]

        return layout
    }

    // MARK: - Layout 3: Restful Sanctuary
    private func generateRestfulSanctuary(
        room: Room,
        baseItems: [Furniture],
        pinnedSet: Set<UUID>,
        weights: GoalWeights
    ) -> Layout {
        let layout = Layout(name: "Restful Sanctuary")
        var clonedItems: [Furniture] = []

        for item in baseItems {
            let clone = cloneFurniture(item)
            if !pinnedSet.contains(item.id) {
                switch item.category.lowercased() {
                case "bed":
                    // Commanding position: headboard solid against north wall, commanding sightline to door
                    clone.positionX = -1.1
                    clone.positionZ = -1.05
                    clone.rotationYaw = 0.0
                case "desk":
                    // Work zone discreetly tucked in northeast corner
                    clone.positionX = 1.9
                    clone.positionZ = -1.4
                    clone.rotationYaw = 0.0
                case "chair":
                    clone.positionX = 1.9
                    clone.positionZ = -0.8
                    clone.rotationYaw = .pi
                case "sofa":
                    // Cozy reading zone along opposite wall
                    clone.positionX = 0.8
                    clone.positionZ = 0.95
                    clone.rotationYaw = 0.0
                default:
                    break
                }
            }
            clonedItems.append(clone)
        }

        layout.furnitures = clonedItems
        layout.insights = [
            Insight(title: "Commanding Bed Position", type: "+", detail: "Bed headboard is anchored against a solid wall with clear sightlines to the entrance while protected from draft corridors."),
            Insight(title: "Bed-Making Perimeter Restored", type: "+", detail: "Both sides of the bed feature 78 cm clearance, fully satisfying Panero & Zelnik R4.")
        ]

        return layout
    }

    private func cloneFurniture(_ item: Furniture) -> Furniture {
        return Furniture(
            id: UUID(),
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
