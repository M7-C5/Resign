# ADR 0011: LightDraft Transient Value Type for Ceiling Grid Editing

* Status: accepted
* Date: 2026-10-20
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

The `LightingSetupView` presents a 5×5 interactive ceiling grid where users tap cells to place, configure (Kelvin color temperature and lumens brightness), and delete artificial light fixtures before confirming and saving. A key UX requirement is that the user can freely back out at any point — including mid-slider-drag — without leaving orphaned `Light` SwiftData records.

Directly inserting a `Light` SwiftData `@Model` into `ModelContext` on every tap, and then deleting it on back, creates three problems:
1. **Orphaned records** if the app is force-quit between tap and delete.
2. **SwiftData change notifications** fire on every slider tick (60 fps drag events), causing unnecessary SwiftUI redraws and potential `@Query` re-evaluation in sibling views.
3. **Discard semantics** are harder to implement cleanly — rolling back requires tracking exactly which `Light` instances were inserted in this session.

## Decision Drivers

* Clean discard / rollback on "Go Back" with zero orphaned records.
* No SwiftData mutation during slider interactions (performance isolation).
* Alignment with existing `@Model` schema (`Light`) — no new persistent types.
* Testability of ViewModel logic independently of SwiftData containers.

## Considered Options

1. **Option A: Direct SwiftData `Light` mutation on tap**: Insert on tap, delete on discard. Simple but creates orphan risk and performance issues during slider events.
2. **Option B: Background `ModelContext`, merge on save**: Separate transient context discarded on back. Correct semantics but non-trivial SwiftData merge APIs and overkill for a 25-cell grid.
3. **Option C: `LightDraft` value-type buffer, bulk-persist on save**: In-memory `[LightDraft]` array owned by the ViewModel; `Light` records are only inserted when the user confirms "Save & Continue".

## Decision Outcome

Chosen option: **Option C — `LightDraft` transient value type**.

### Contract

```swift
public struct LightDraft: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var gridColumn: Int   // 0–4  → persisted as Light.coordinateX
    public var gridRow: Int      // 0–4  → persisted as Light.coordinateY
    public var name: String      // Auto-named "Lighting N"
    public var brightness: Float // Lumens 500–3000
    public var colorTemp: Int    // Kelvin 2200–6500
    public var isOn: Bool
}
```

The `LightingSetupViewModel` owns `var drafts: [LightDraft]` and bulk-converts them to `Light` SwiftData records only in `saveToLayout(_:context:)` when the user confirms "Save & Continue".

### Coordinate Mapping

| `LightDraft` field | `Light` SwiftData field | Notes |
|:---|:---|:---|
| `gridColumn` (Int 0–4) | `coordinateX` (Float) | Cast: `Float(gridColumn)` |
| `gridRow` (Int 0–4) | `coordinateY` (Float) | Cast: `Float(gridRow)` |
| — | `elevationZ` | Fixed ceiling height `2.6` m |

### Consequences

* `LightingSetupViewModel` is fully unit-testable without a SwiftData container (draft operations only).
* SwiftData is touched exactly once, on user-confirmed save, at the end of the session.
* Future sub-cell precision (e.g., dragging a light to exact fractional positions) requires only widening the `Int` columns to `Double`/`Float` — the `Light` model already stores `Float`.
