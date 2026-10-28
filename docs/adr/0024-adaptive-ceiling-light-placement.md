# ADR 0024: Adaptive Ceiling Light Placement

- Status: Accepted
- Date: 2026-10-28
- Amends: [ADR 0011](0011-lightdraft-transient-edit-pattern.md), [ADR 0023](0023-render-selected-scanned-layout-lighting.md)

## Context

A fixed five-by-five placement grid creates stretched spacing in long rooms and offers points outside concave scanned footprints. Changing the number of grid cells must not move saved fixtures or change their simulated positions.

## Decision Drivers

- Derive placement density from the captured wall bounds and room proportions.
- Keep new points inside a closed scanned perimeter.
- Preserve existing lights and provide at least 44-point targets for new placement points.
- Retain the existing SwiftData schema and transient edit/discard behavior.

## Considered Options

1. Persist variable grid row/column counts: rejected because resizing or changing density could move saved lights.
2. Separate normalized fixture positions from the candidate lattice: chosen because positions stay stable independently of point count and display size.

## Decision Outcome

Generate candidate cell centers with roughly 0.85-meter spacing, increasing spacing when necessary to fit 44-point touch targets in the displayed plan. Row and column counts follow the room's aspect ratio, rather than always using five of each. A closed, connected wall perimeter filters candidates by an even-odd point-in-polygon test; incomplete wall traces use the existing rectangular bounds explicitly. Furniture does not exclude ceiling positions.

Drafts retain normalized plan coordinates in addition to the legacy integer grid fields. Preserve the existing persisted coordinate convention with `coordinateX = normalizedX * 5 - 0.5` and the corresponding Z/row value. Integer values 0 through 4 therefore retain their previous positions; adaptive points may use fractional values from -0.5 through 4.5. The selected-layout renderer decodes the same coordinates without snapping them to a candidate grid. No persistent attributes are added.

Render saved drafts independently of the generated candidates, so changing density or reopening configuration does not snap, hide, or delete an existing light. New empty points within 20 display points of saved lights are suppressed to avoid drawing dots beneath bulb markers; neighboring points remain visible so editing does not create large gaps. The plan uses more of the available screen width and height while retaining 44-point button targets. All mutations stay transient until Save; existing identity-based reconciliation remains in place.

## Consequences

- Long, square, and concave rooms get different candidate layouts.
- Existing integer-grid fixtures remain editable at their original positions.
- Incomplete or disconnected scans cannot reliably define an interior, so rectangular fallback may still offer points outside an unknown footprint.
- Previously saved lamps outside a newly detected boundary remain visible and removable.

## Validation

Unit tests cover long and portrait rooms, balanced spacing, display-density limits, an L-shaped perimeter, incomplete-perimeter fallback, fractional-position save/reopen/render round trips, and legacy coordinate preservation. Run `./scripts/verify.sh` for compilation and isolated unit tests.
