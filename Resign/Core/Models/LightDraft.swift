//
//  LightDraft.swift
//  Resign
//

import Foundation

/// Transient, in-memory representation of a light fixture during adaptive ceiling placement.
///
/// `LightDraft` decouples live slider interactions from SwiftData by holding all
/// edits in memory until the user confirms "Save & Continue". At that point,
/// `LightingSetupViewModel.saveToLayout(_:context:)` bulk-converts drafts into
/// persisted `Light` SwiftData records.
///
/// - SeeAlso: ADR 0011 — LightDraft Transient Value Type for Ceiling Grid Editing
/// - SeeAlso: `LightingSetupViewModel.saveToLayout(_:context:)`
public struct LightDraft: Identifiable, Sendable, Equatable {

    /// Stable identity across the editing session.
    public var id: UUID

    /// Legacy column index (0 = left, 4 = right), used when no exact plan position is supplied.
    public var gridColumn: Int

    /// Legacy row index (0 = top, 4 = bottom), used when no exact plan position is supplied.
    public var gridRow: Int

    /// Exact normalized plan position for adaptive placement; nil retains legacy grid semantics.
    public var planPosition: SIMD2<Float>?

    public var unitPosition: SIMD2<Float> {
        planPosition ?? SIMD2<Float>((Float(gridColumn) + 0.5) / 5, (Float(gridRow) + 0.5) / 5)
    }

    /// Display name shown in the bottom panel, e.g. "Lighting 1".
    public var name: String

    /// Luminosity in lumens. Valid range: 500–3000 lm.
    public var brightness: Float

    /// Correlated color temperature in Kelvin. Valid range: 2200 K (warm) – 6500 K (daylight).
    public var colorTemp: Int

    /// Whether the fixture is switched on. Defaults to `true`.
    public var isOn: Bool

    public init(
        id: UUID = UUID(),
        gridColumn: Int,
        gridRow: Int,
        name: String = "Lighting",
        brightness: Float = 1080.0,
        colorTemp: Int = 5000,
        isOn: Bool = true,
        planPosition: SIMD2<Float>? = nil
    ) {
        self.planPosition = planPosition
        self.id = id
        self.gridColumn = gridColumn
        self.gridRow = gridRow
        self.name = name
        self.brightness = brightness
        self.colorTemp = colorTemp
        self.isOn = isOn
    }
}
