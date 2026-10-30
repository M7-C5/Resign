//
//  Studio3DViewModel.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation
import Observation
import UIKit
import SwiftUI

/// A floor-level operational clearance highlight for furniture involved in a spatial violation.
public struct ViolationMarker: Identifiable, Hashable, Sendable {
    public var id: String
    public var ruleId: String
    public var title: String
    public var severity: ViolationSeverity
    public var measuredCm: Double
    public var requiredCm: Double
    /// Room-space footprint in meters (same frame as `Furniture` positions).
    public var centerX: Float
    public var centerZ: Float
    public var sizeX: Float
    public var sizeZ: Float
    /// Clearance operational zone radius in meters.
    public var clearanceRadius: Float

    // Contextual Door Swing Geometry
    public var isDoorSwing: Bool
    public var doorPivotX: Float
    public var doorPivotZ: Float
    public var doorSwingRadius: Float
    public var doorStartAngle: Float
    public var doorSweepAngle: Float

    public init(
        id: String,
        ruleId: String,
        title: String,
        severity: ViolationSeverity,
        measuredCm: Double,
        requiredCm: Double,
        centerX: Float,
        centerZ: Float,
        sizeX: Float,
        sizeZ: Float,
        clearanceRadius: Float = 0.85,
        isDoorSwing: Bool = false,
        doorPivotX: Float = 0,
        doorPivotZ: Float = 0,
        doorSwingRadius: Float = 0.9,
        doorStartAngle: Float = 0,
        doorSweepAngle: Float = -Float.pi / 2.0
    ) {
        self.id = id
        self.ruleId = ruleId
        self.title = title
        self.severity = severity
        self.measuredCm = measuredCm
        self.requiredCm = requiredCm
        self.centerX = centerX
        self.centerZ = centerZ
        self.sizeX = sizeX
        self.sizeZ = sizeZ
        self.clearanceRadius = clearanceRadius
        self.isDoorSwing = isDoorSwing
        self.doorPivotX = doorPivotX
        self.doorPivotZ = doorPivotZ
        self.doorSwingRadius = doorSwingRadius
        self.doorStartAngle = doorStartAngle
        self.doorSweepAngle = doorSweepAngle
    }
}

@Observable
public final class Studio3DViewModel {
    public var highlightedFurnitureIDs: Set<UUID> = []
    public var selectedFurnitureID: UUID? = nil
    public var violationMarkers: [ViolationMarker] = []
    public var showViolations: Bool = true

    /// Active layout being represented in the 3D studio
    public var currentLayout: Layout? = nil
    public var shouldAnimateLayoutChange: Bool = true
    public var activeLayoutVersion: Int = 0

    public init() {}

    /// Applies a layout to the 3D studio, moving furniture entities to match layout positions
    public func applyLayout(_ layout: Layout, animated: Bool = true) {
        self.currentLayout = layout
        self.shouldAnimateLayoutChange = animated
        self.activeLayoutVersion += 1
    }

    /// Sets vibrant floor clearance highlights for recommended layouts showing compliant operational zones.
    public func setRecommendationHighlights(for layout: Layout) {
        let engine = SpatialClearanceEngine()
        var markers: [ViolationMarker] = []

        for item in layout.furnitures where !item.isArchived {
            let box = engine.boundingBox(for: item)
            let buffer: Float = (item.category == "desk" || item.category == "bed") ? 0.35 : 0.20
            let marker = ViolationMarker(
                id: "optimal-\(item.id)",
                ruleId: "OPT",
                title: "\(item.name) Clear Operational Flow",
                severity: .warning,
                measuredCm: 90.0,
                requiredCm: 76.2,
                centerX: box.centerX,
                centerZ: box.centerZ,
                sizeX: box.width + buffer,
                sizeZ: box.length + buffer,
                clearanceRadius: max(box.width, box.length) * 0.55
            )
            markers.append(marker)
        }
        self.violationMarkers = markers
    }

    /// Builds operational clearance markers per furniture item involved in each violation,
    /// calculating exact door swing arc geometry when doors are provided.
    public func setViolations(_ violations: [SpatialViolation], in layout: Layout, doors: [RoomOpening] = []) {
        let engine = SpatialClearanceEngine()
        let furniture = Dictionary(layout.furnitures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        violationMarkers = violations.flatMap { violation in
            violation.itemIds.compactMap { furniture[$0] }.map { item in
                let box = engine.boundingBox(for: item)
                let footprintRadius = max(box.width, box.length) * 0.5
                let requiredBufferMeters = Float(violation.requiredClearanceCm / 100.0)
                let radius = max(footprintRadius + (requiredBufferMeters * 0.45), requiredBufferMeters)

                var isDoor = false
                var pivotX: Float = box.centerX
                var pivotZ: Float = box.centerZ
                var swingRad: Float = requiredBufferMeters > 0 ? requiredBufferMeters : 0.90
                var startAngle: Float = 0.0
                var sweepAngle: Float = -Float.pi / 2.0

                if violation.ruleId == PaneroZelnikRule.doorSwingUnobstructed {
                    isDoor = true
                    // Find the door closest to this obstructing furniture item
                    let matchedDoor = doors.min(by: { d1, d2 in
                        let dist1 = hypot(d1.posX - box.centerX, d1.posZ - box.centerZ)
                        let dist2 = hypot(d2.posX - box.centerX, d2.posZ - box.centerZ)
                        return dist1 < dist2
                    })

                    if let door = matchedDoor {
                        swingRad = door.width
                        if abs(door.posZ) >= abs(door.posX) {
                            // North or South wall
                            if door.posZ > 0 {
                                // South wall (Z > 0), door swings inward North (-Z)
                                let hingeX = door.posX < 0 ? (door.posX - door.width / 2.0) : (door.posX + door.width / 2.0)
                                pivotX = hingeX
                                pivotZ = door.posZ
                                if door.posX < 0 {
                                    startAngle = 0.0
                                    sweepAngle = -Float.pi / 2.0
                                } else {
                                    startAngle = Float.pi
                                    sweepAngle = Float.pi / 2.0
                                }
                            } else {
                                // North wall (Z < 0), door swings inward South (+Z)
                                let hingeX = door.posX < 0 ? (door.posX - door.width / 2.0) : (door.posX + door.width / 2.0)
                                pivotX = hingeX
                                pivotZ = door.posZ
                                if door.posX < 0 {
                                    startAngle = 0.0
                                    sweepAngle = Float.pi / 2.0
                                } else {
                                    startAngle = Float.pi
                                    sweepAngle = -Float.pi / 2.0
                                }
                            }
                        } else {
                            // East or West wall
                            if door.posX > 0 {
                                // East wall (X > 0), swings inward West (-X)
                                pivotX = door.posX
                                pivotZ = door.posZ < 0 ? (door.posZ - door.width / 2.0) : (door.posZ + door.width / 2.0)
                                startAngle = Float.pi / 2.0
                                sweepAngle = Float.pi / 2.0
                            } else {
                                // West wall (X < 0), swings inward East (+X)
                                pivotX = door.posX
                                pivotZ = door.posZ < 0 ? (door.posZ - door.width / 2.0) : (door.posZ + door.width / 2.0)
                                startAngle = Float.pi / 2.0
                                sweepAngle = -Float.pi / 2.0
                            }
                        }
                    } else {
                        // Fallback when doors array not supplied
                        pivotX = box.centerX
                        pivotZ = box.maxZ
                        startAngle = 0.0
                        sweepAngle = -Float.pi / 2.0
                    }
                }

                return ViolationMarker(
                    id: "\(violation.id)-\(item.id)",
                    ruleId: violation.ruleId,
                    title: violation.ruleTitle,
                    severity: violation.severity,
                    measuredCm: violation.measuredClearanceCm,
                    requiredCm: violation.requiredClearanceCm,
                    centerX: box.centerX,
                    centerZ: box.centerZ,
                    sizeX: box.width,
                    sizeZ: box.length,
                    clearanceRadius: radius,
                    isDoorSwing: isDoor,
                    doorPivotX: pivotX,
                    doorPivotZ: pivotZ,
                    doorSwingRadius: swingRad,
                    doorStartAngle: startAngle,
                    doorSweepAngle: sweepAngle
                )
            }
        }
    }

    public func clearViolations() {
        violationMarkers.removeAll()
    }

    public func highlightFurniture(ids: Set<UUID>) {
        highlightedFurnitureIDs = ids
    }

    public func clearHighlights() {
        highlightedFurnitureIDs.removeAll()
    }

    public func isHighlighted(_ id: UUID) -> Bool {
        highlightedFurnitureIDs.contains(id)
    }

    public func toggleHighlight(for id: UUID) {
        if highlightedFurnitureIDs.contains(id) {
            highlightedFurnitureIDs.remove(id)
        } else {
            highlightedFurnitureIDs.insert(id)
        }
    }
}

// MARK: - Rule-Specific Color Theme

public extension ViolationMarker {
    /// Distinct, harmonious accent color for each spatial clearance rule.
    var uiColor: UIColor {
        switch ruleId {
        case "OPT", "FLOW":
            // Vibrant Spring Emerald / Cyan for optimal flow & clearance
            return UIColor(red: 0.18, green: 0.82, blue: 0.65, alpha: 1.0)
        case PaneroZelnikRule.walkwayCritical:
            // R1: Crisp Coral Red
            return UIColor(red: 0.95, green: 0.28, blue: 0.30, alpha: 1.0)
        case PaneroZelnikRule.walkwayRecommended:
            // R2: Warm Amber / Gold
            return UIColor(red: 0.98, green: 0.62, blue: 0.15, alpha: 1.0)
        case PaneroZelnikRule.deskRearClearance:
            // R3: Electric Cobalt / Sky Blue
            return UIColor(red: 0.15, green: 0.55, blue: 0.98, alpha: 1.0)
        case PaneroZelnikRule.bedOperationalZone:
            // R4: Spring Mint Green
            return UIColor(red: 0.18, green: 0.78, blue: 0.44, alpha: 1.0)
        case PaneroZelnikRule.bedStorageZone:
            // R5: Ocean Cyan / Teal
            return UIColor(red: 0.15, green: 0.72, blue: 0.82, alpha: 1.0)
        case PaneroZelnikRule.doorSwingUnobstructed:
            // R6: Royal Violet / Purple
            return UIColor(red: 0.68, green: 0.32, blue: 0.95, alpha: 1.0)
        default:
            return severity == .critical
                ? UIColor(red: 0.95, green: 0.28, blue: 0.30, alpha: 1.0)
                : UIColor(red: 0.98, green: 0.62, blue: 0.15, alpha: 1.0)
        }
    }

    var swiftUIColor: Color {
        Color(uiColor: uiColor)
    }
}
