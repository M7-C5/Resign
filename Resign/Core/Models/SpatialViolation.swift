//
//  SpatialViolation.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation

public enum ViolationSeverity: String, Codable, Sendable {
    case critical
    case warning
}

public struct SpatialViolation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var ruleId: String
    public var ruleTitle: String
    public var severity: ViolationSeverity
    public var measuredClearanceCm: Double
    public var requiredClearanceCm: Double
    public var itemIds: [UUID]
    public var message: String

    public init(
        id: UUID = UUID(),
        ruleId: String,
        ruleTitle: String,
        severity: ViolationSeverity,
        measuredClearanceCm: Double,
        requiredClearanceCm: Double,
        itemIds: [UUID],
        message: String
    ) {
        self.id = id
        self.ruleId = ruleId
        self.ruleTitle = ruleTitle
        self.severity = severity
        self.measuredClearanceCm = measuredClearanceCm
        self.requiredClearanceCm = requiredClearanceCm
        self.itemIds = itemIds
        self.message = message
    }
}

public struct PaneroZelnikRule: Sendable {
    /// Walkways critical clearance threshold: 76.2 cm (30 inches)
    public static let walkwayCritical = "R1"
    
    /// Walkways recommended clearance threshold: 91.4 cm (36 inches)
    public static let walkwayRecommended = "R2"
    
    /// Desk rear clearance for chair pull-back and seated egress: 76.2 cm (30 inches)
    public static let deskRearClearance = "R3"
    
    /// Bed operational zone for bed-making: 66.0 – 99.0 cm (26 – 39 inches)
    public static let bedOperationalZone = "R4"
    
    /// Under-bed drawer / storage operational clearance: 116.0 – 157.0 cm (46 – 62 inches)
    public static let bedStorageZone = "R5"
    
    /// Door swing must remain 100% unobstructed (0 cm margin allowed)
    public static let doorSwingUnobstructed = "R6"
}
