//
//  LightingSetupViewModel.swift
//  Resign
//

import Foundation
import Observation
import SwiftData

/// ViewModel for the 5×5 ceiling-grid lighting placement screen.
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

    /// All light fixtures placed on the 5×5 ceiling grid (unsaved).
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

    public init() {}

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

    /// Bulk-converts all `LightDraft` values into `Light` SwiftData records and
    /// appends them to the provided `Layout`, then saves the context.
    ///
    /// This is the **only** function that touches `ModelContext` — all prior
    /// interactions operate on in-memory `LightDraft` values.
    ///
    /// - Parameters:
    ///   - layout: The `Layout` record that will own the new `Light` instances.
    ///   - context: The `ModelContext` to insert into and save.
    /// - Throws: Re-throws any `ModelContext.save()` error.
    func saveToLayout(_ layout: Layout, context: ModelContext) throws {
        for draft in drafts {
            let light = Light(
                name: draft.name,
                coordinateX: Float(draft.gridColumn),
                coordinateY: Float(draft.gridRow),
                elevationZ: 2.6,
                brightness: draft.brightness,
                colorTemp: draft.colorTemp,
                isOn: draft.isOn
            )
            layout.lights.append(light)
            context.insert(light)
        }
        try context.save()
    }

    // MARK: - Private Helpers

    /// Returns the next sequential light name, e.g. "Lighting 1", "Lighting 2".
    private func nextLightName() -> String {
        "Lighting \(drafts.count + 1)"
    }
}
