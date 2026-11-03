# ADR 0034: Aperture-Aware Ceiling Outline Validation

- Status: Accepted
- Date: 2026-10-30
- Amends: [ADR 0024](0024-adaptive-ceiling-light-placement.md)

## Context

Configure Lighting rejects any captured wall trace that cannot form a closed perimeter. A door or other aperture can split a wall into separate captured segments, so endpoint-only joining can label a usable scan as incomplete. Zero-length segments also prevent perimeter matching.

## Decision

Pass saved aperture centers and widths to the pure ceiling placement engine. The view transforms centers from world coordinates into the saved scan frame. Ignore wall segments no longer than 1 cm after rejecting nonfinite coordinates. Add a boundary bridge only between outward-facing collinear segment ends, within 1 cm of the same supporting line, when a saved aperture matches the gap midpoint within 15 cm and its width within 30 cm. Merge these bridges using existing fragment normalization, then apply the existing reciprocal corner matching, single-cycle, intersection, interior, and wall-clearance checks.

Use the same aperture evidence for display-density candidate generation and saved-light validation. No persistence schema changes are required.

## Alternatives

- A rectangular fallback would offer points in unknown areas and concave cutouts, so it remains rejected.
- Increasing all endpoint tolerances could bridge unrelated recesses; aperture evidence constrains the repair instead.

## Consequences

Existing scans can recover placement across matching captured apertures without rescanning. Missing sides, unrelated openings, and unresolved disconnected or ambiguous geometry remain blocked. This does not infer arbitrary missing walls or reconstruct interior partition topology.

## Validation

Unit tests cover a door-sized split, rotated/reversed capture order, mismatched aperture positions and widths, missing-side rejection, zero-length artifacts, and the existing concave-room regressions. Run `./scripts/verify.sh` for compilation and isolated unit tests.
