# ADR 0035: Separate Ceiling Perimeter from Open Interior Wall Branches

- Status: Accepted
- Date: 2026-10-30
- Amends: [ADR 0024](0024-adaptive-ceiling-light-placement.md), [ADR 0034](0034-aperture-aware-ceiling-outline.md)

## Context

A failing iPad scan contains eight perimeter segments forming a closed room and a ninth segment extending inward from a perimeter corner. Requiring every captured segment to belong to one cycle incorrectly disables ceiling configuration. Aperture repair cannot resolve an interior branch.

## Decision

After fragment merging and evidence-based aperture bridging, repeatedly remove segments having an endpoint with no eligible corner partner on another segment. Repeat until no further open branches can be removed. Apply existing reciprocal corner matching, single-cycle and intersection validation to the remaining perimeter candidates. Require every captured wall midpoint to lie inside the recovered perimeter or within 25 cm of it. This prevents a surviving closed interior island from replacing an incomplete outer trace. Missing room sides without a supported enclosing perimeter still fail. Multiple surviving cycles remain ambiguous and are rejected; do not select a largest loop or infer a rectangular footprint.

Keep all nondegenerate captured walls separately for clearance checks. A pruned interior partition therefore cannot disable a valid perimeter, but still excludes nearby ceiling placement points. Use the same engine for new candidates and saved-light validation. No persistence changes are required.

## Consequences

Closed rooms with dangling interior partitions can configure lights. Incomplete traces, ambiguous loops, and connected interior cycles remain outside this repair. The regression fixture retains only wall geometry from the failing device scan, without room identity or world location.

## Validation

Tests reproduce the captured iPad geometry, reversed segment order and direction, a chain of interior branches, clearance along pruned partitions, rejection after removal of a perimeter side, and a closed interior island inside an incomplete outer trace. Existing concave, aperture, and incomplete-outline tests remain required. Run `./scripts/verify.sh` before installing the device build.
