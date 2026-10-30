# ADR 0012: Foundation Model Tool Calling over a Single-Source-of-Truth Geometry Core and Constraint-Driven Layout Solver

* Status: accepted
* Date: 2026-10-28
* Deciders: Lead Developer, Antigravity Agent
* Supersedes (in part): the solver description in [ADR 0011](0011-dynamic-parametric-spatial-solver-and-perimeter-zoning.md)

## Context and Problem Statement

Manual testing of layout recommendations surfaced three recurring defects:

1. **Overlapping furniture** in generated layouts and in the 3D scene.
2. **Near-identical recommendations** across the three variants.
3. **User intent ignored** (free-text requests such as "keep the TV", "desk by the window", "more space to move around").

Root-cause analysis found problems below the LLM layer, which prompt engineering alone cannot fix:

* **Geometry disagreement.** The fixture room stored the desk and chair at `yaw = π/2` while the shipped 3D meshes (and the USDZ loader, which reports `yaw = 0`) are authored at yaw 0. The clearance engine therefore validated different geometry than the one rendered.
* **Axis-blind desk rule (R3).** Desk pull-back clearance was always measured along Z regardless of the direction the chair is actually pulled.
* **Coordinate-table solver.** The previous solver still assigned hand-tuned coordinates per variant (including a free-standing TV console when the TV was not pinned) and only *declared* itself parametric.
* **Intent never reached the solver.** Free text was turned into insight cards, but only pinning influenced layout generation.
* **No measurement channel for the model.** Apple Foundation Models cannot compute collision geometry reliably; they were asked to reason about geometry they could not measure.

## Decision Drivers

* The model must **never** invent geometry; it may only read verified measurements and register user intent.
* Every consumer (clearance rules, validator, solver, tools, 3D view) must agree on one footprint and orientation convention.
* Behaviour must be identical on device and in Simulator/CI, where the on-device model is unavailable.
* All new logic must be unit-testable in sub-second runs without the model.

## Decision Outcome

### 1. Single orientation and footprint convention

Every category declares the wall-facing ("back") direction of its mesh at `yaw = 0` (bed: north, desk: east, chair: west, sofa: south, wardrobe: west, TV: north). `FurnitureOrientation` derives the yaw that points an item's back at a wall. Footprints are always `SpatialClearanceEngine.boundingBox(for:)`. Fixture data was corrected to match the meshes.

### 2. Constraint-driven solver

`LayoutOptimizerEngine` enumerates perimeter candidates for each item (wall × yaw × slide position), applies **hard filters** (bounds, no overlap, door swing, window sill, Panero & Zelnik critical rules, TV–sofa sightline) with a documented relaxation ladder, then **scores** candidates per strategy (window light, door distance, corners, central plaza, TV viewing distance). Variants 2 and 3 are penalised for repeating earlier variants' placements to guarantee perceptible differences. `LayoutConstraints` (desk near window, open circulation, quiet sleeping, TV sightline) plus pins are inputs to every variant.

### 3. Validation engine

`LayoutValidationEngine` reports overlaps, out-of-bounds items, blocked TV sightline and all Panero & Zelnik violations, and is the shared oracle for the solver tests and the model tools.

### 4. Foundation Model tools

`LanguageModelSession` is created with tools backed by pure Swift engines:

| Tool | Purpose |
| :--- | :--- |
| `measureClearance` | Exact centimetre gap/overlap between two items, or an item and a wall. |
| `registerUserConstraint` | Locks a user intent (pin an item, desk near window, open circulation, quiet sleeping) into solver constraints. |
| `previewVariant` | Runs the deterministic solver for a strategy and returns its validated outcome so the model explains verified results instead of guessing. |

**Deterministic backstop:** after the model responds, constraints parsed from the user's chips and free text by `UserConstraintParser` are merged into the solver settings regardless of whether the model called a tool. The Simulator/rulebook path uses the same parser, so intent handling is identical everywhere.

## Consequences

* **Positive:** overlaps, near-identical variants and ignored intent are each covered by deterministic tests across several room sizes and door/window placements. The model's role is bounded and grounded.
* **Negative / limits:**
  * Tool calling can only be exercised on a physical Apple Intelligence device; Simulator and CI verify the tools by invoking them directly and verify the pipeline through the deterministic path.
  * Keyword parsing of free text has no negation handling ("I don't want it spacious" is read as spacious).
  * The greedy solver is not globally optimal; in very small rooms it relaxes separation rules and reports remaining violations rather than failing.
