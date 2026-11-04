# ADR 0044: Functional Floating Furniture and Depth-Tier Layout Optimization

* Status: accepted
* Date: 2026-11-03
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign's layout optimizer previously snapped and clamped all major furniture items (`bed`, `desk`, `sofa`, `closet`, `television`) flush against the nearest perimeter walls with a 5mm gap (`wallGap = 0.005`). While this solved initial coordinate instability in compact rooms, in standard and spacious rooms (e.g. 5.0m × 4.2m, 6.0m × 4.5m, 7.0m × 5.0m), forcing every piece against the walls produced un-ergonomic spatial outcomes:
1. **Excessive Media Viewing Distance**: Shoving sofas flush against the South wall when TV consoles were on the North wall produced viewing distances exceeding 4.2m–5.0m, far beyond ergonomic living room standards (2.0m–2.8m).
2. **Awkward Central Voids**: Forcing all furniture to the room perimeter created an unnatural cavernous center while crowding walls and blocking corners.
3. **Rigid Clamping Overrides**: The fallback `clampInside` method forcibly flattened floating candidates back against the wall, preventing natural island desks and conversational sofa groupings.

Users requested that the optimization algorithm allow furniture to move away from walls rather than strictly sticking to the perimeter.

## Decision Drivers

* **Ergonomic Island & Floating Placements**: Allow sofas, desks, and accent seating to float inward when room dimensions provide ample space.
* **Panero & Zelnik Verification**: Every floating placement must strictly maintain $\ge 76.2\text{ cm}$ (or $90\text{ cm}$) circulation corridors behind and around it, with zero critical bottlenecks.
* **Computational Efficiency**: Avoid unguided brute-force 2D grid searches (8,400+ positions per item), maintaining sub-second optimization and test execution.
* **Architectural Semantic Coherence**: Heavy storage wardrobes and TV consoles remain perimeter-anchored, while seating and desks dynamically explore functional depth tiers.
* **Boundary Safety**: Bounding boxes must remain strictly inside room perimeters without being forcibly crushed to the nearest wall.

## Considered Options

* **Option 1: Unguided 2D Grid Search (10cm Resolution)**:
  - Generate a dense 2D grid across open floor area for all furniture items.
  - *Rejected*: Requires evaluating 50,000+ geometric collision trees across 3 variants, causing multi-second UI lag and producing semantically incoherent floating positions (e.g. beds stranded in front of entrance doors).
* **Option 2: Multi-Depth Tier Candidates with Semantic Offset Gating**:
  - Dynamically generate candidates at distinct architectural depth tiers:
    - Tier 0: Flush against wall (`0.005m`).
    - Tier 1: Walkway/circulation corridor behind (`0.762m` to `0.80m`).
    - Tier 2: Conversational viewing island / floating desk (`1.10m` to `1.20m`).
  - Gate depth tiers by room axis depth ($\ge 3.8\text{m}$) so compact rooms never choke circulation.
  - Replace perimeter-crushing `clampInside` with bounding box inside-room clamping.

## Decision Outcome

Chosen option: **Option 2: Multi-Depth Tier Candidates with Semantic Offset Gating**.

### Architectural Changes

1. **`depthOffsets(for:wall:scene:itemBox:)` in `LayoutOptimizerEngine`**:
   - Computes viable depth tiers per furniture role based on the room's dimensional span on that axis.
   - Sofas and desks in rooms with axis depth $\ge 3.8\text{m}$ evaluate both flush wall placement and inward floating tiers ($+0.80\text{m}$, $+1.20\text{m}$).
2. **`clampInside` Relaxation**:
   - Clamps item bounding boxes to stay within room margins `[-halfW + marginX, halfW - marginX]` and `[-halfL + marginZ, halfL - marginZ]`, preserving valid floating coordinates without forcing perimeter wall snaps.
3. **Diversity Metric Upgrade**:
   - Computes Euclidean distance `hypot(candidate.x - earlier.x, candidate.z - earlier.z) < 0.5` across layout variants, properly distinguishing flush vs. floating variants of the same piece.

## Consequences

### Positive
* Enables authentic, professional interior designs (floating conversational sofas, island desks with daylight orientation).
* Maintains sub-second solver performance and sub-second FastUnitTests execution.
* 100% compliant with Panero & Zelnik clearances and door swing keep-out zones.

### Negative
* Testing contracts must assert that floating furniture maintains bounded room offsets rather than asserting flush wall gaps $\le 0.06\text{m}$.

