//
//  LightingSetupViewModel.swift
//  Resign
//

import Foundation
import Observation
import SwiftData

/// ViewModel for adaptive ceiling-light placement.
///
/// Holds a transient `[LightDraft]` buffer during the editing session.
/// SwiftData is only touched when the user confirms "Save & Continue" via
/// `saveToLayout(_:context:)`. All slider mutations operate on value-type
/// drafts, producing zero SwiftData change notifications during interaction.
///
/// - SeeAlso: ADR 0011 — LightDraft Transient Value Type for Ceiling Grid Editing
@Observable
@MainActor
public final class LightingSetupViewModel {

    // MARK: - Grid State

    /// All light fixtures placed in the room plan (unsaved).
    var drafts: [LightDraft] = []

    /// The `id` of the currently tapped / selected draft. `nil` = no selection.
    var selectedDraftID: UUID? = nil

    // MARK: - Confirmation Dialog Flags

    var showSaveConfirm: Bool = false
    var showBackConfirm: Bool = false
    var showDeleteConfirm: Bool = false

    // MARK: - Save Error

    /// Non-nil when `saveToLayout` throws. Surfaced as an alert in the view.
    var saveError: String? = nil

    // MARK: - Computed

    /// The currently selected draft, if any.
    var selectedDraft: LightDraft? {
        drafts.first { $0.id == selectedDraftID }
    }

    @ObservationIgnored private var loadedLayoutID: UUID?
    private var hadSavedLights = false

    /// An existing setup may be saved empty to remove its final fixture.
    var canSave: Bool { !drafts.isEmpty || hadSavedLights }

    public init() {}

    /// Copy persisted fixtures once per editing session, preserving unsaved edits on reappearance.
    func loadFromLayout(_ layout: Layout) {
        guard loadedLayoutID != layout.id else { return }
        loadedLayoutID = layout.id
        hadSavedLights = !layout.lights.isEmpty
        selectedDraftID = nil
        drafts = layout.lights.sorted { $0.name < $1.name }.map { light in
            LightDraft(id: light.id,
                       gridColumn: Int(min(4, max(0, light.coordinateX)).rounded()),
                       gridRow: Int(min(4, max(0, light.coordinateY)).rounded()),
                       name: light.name, brightness: light.brightness,
                       colorTemp: light.colorTemp, isOn: light.isOn,
                       planPosition: SIMD2<Float>((light.coordinateX + 0.5) / 5, (light.coordinateY + 0.5) / 5))
        }
    }

    // MARK: - Grid Interaction

    /// Handles a tap on the grid at `(col, row)`.
    ///
    /// - If a draft already exists at that position it is selected.
    /// - If the cell is empty a new draft is created, auto-named, and selected.
    func tapCell(col: Int, row: Int) {
        if let existing = drafts.first(where: { $0.gridColumn == col && $0.gridRow == row }) {
            selectedDraftID = existing.id
        } else {
            let newDraft = LightDraft(
                gridColumn: col,
                gridRow: row,
                name: nextLightName()
            )
            drafts.append(newDraft)
            selectedDraftID = newDraft.id
        }
    }

    /// Candidate points carry exact plan coordinates rather than a variable-grid index.
    func tapPosition(_ point: SIMD2<Float>) {
        if let existing = drafts.first(where: {
            abs($0.unitPosition.x - point.x) < 0.0001 && abs($0.unitPosition.y - point.y) < 0.0001
        }) {
            selectedDraftID = existing.id
            return
        }
        let draft = LightDraft(
            gridColumn: Int(min(4, max(0, point.x * 5 - 0.5)).rounded()),
            gridRow: Int(min(4, max(0, point.y * 5 - 0.5)).rounded()),
            name: nextLightName(), planPosition: point
        )
        drafts.append(draft)
        selectedDraftID = draft.id
    }

    /// Clears the current selection without removing the draft.
    func deselectLight() {
        selectedDraftID = nil
    }

    /// Removes the currently selected draft and clears the selection.
    func deleteSelectedDraft() {
        drafts.removeAll { $0.id == selectedDraftID }
        selectedDraftID = nil
    }

    // MARK: - Property Mutators

    /// Updates the brightness (lumens) of the currently selected draft.
    func updateBrightness(_ value: Float) {
        guard let idx = drafts.firstIndex(where: { $0.id == selectedDraftID }) else { return }
        drafts[idx].brightness = value
    }

    /// Updates the color temperature (Kelvin) of the currently selected draft.
    func updateColorTemp(_ value: Int) {
        guard let idx = drafts.firstIndex(where: { $0.id == selectedDraftID }) else { return }
        drafts[idx].colorTemp = value
    }

    // MARK: - Persistence

    /// Reconcile only this layout's fixtures when the user confirms Save.
    /// Existing identities and elevations survive edits; removed drafts delete saved fixtures.
    func saveToLayout(_ layout: Layout, context: ModelContext) throws {
        let saved = layout.lights
        let draftIDs = Set(drafts.map(\.id))
        var updated: [Light] = []
        for draft in drafts {
            let light: Light
            if let existing = saved.first(where: { $0.id == draft.id }) {
                light = existing
            } else {
                light = Light(id: draft.id, elevationZ: max(0.05, layout.room?.height ?? 2.6))
                context.insert(light)
            }
            light.name = draft.name
            light.coordinateX = draft.unitPosition.x * 5 - 0.5
            light.coordinateY = draft.unitPosition.y * 5 - 0.5
            light.brightness = draft.brightness
            light.colorTemp = draft.colorTemp
            light.isOn = draft.isOn
            updated.append(light)
        }
        layout.lights = updated
        for removed in saved where !draftIDs.contains(removed.id) {
            context.delete(removed)
        }
        layout.updatedAt = Date()
        try context.save()
        hadSavedLights = !drafts.isEmpty
    }

    // MARK: - Private Helpers

    /// Returns the next sequential light name, e.g. "Lighting 1", "Lighting 2".
    private func nextLightName() -> String {
        let names = Set(drafts.map(\.name))
        var number = 1
        while names.contains("Lighting \(number)") { number += 1 }
        return "Lighting \(number)"
    }
}
