# ADR 0041: Dynamic Parametric Spatial Solver and Perimeter Functional Zoning

* Status: accepted
* Date: 2026-10-27
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign's initial layout optimizer utilized fixed target coordinates for furniture pieces across its three generated variants (`Circadian Productivity`, `Open Flow & Circulation`, and `Restful Sanctuary`). While mathematically conforming to Panero & Zelnik clearances in standard 5.0m × 4.2m benchmark rooms, hardcoded offsets exhibit severe architectural and spatial flaws when room geometry changes or when items are pinned:
1. **Geometric Inelasticity**: In non-standard room dimensions (e.g. 4.0m × 3.5m) or alternate door/window placements, fixed numbers cause pieces to float in room circulation axes or collide with walls.
2. **"Floating Island" Ergonomic Failure**: To avoid collisions with a pinned North-wall TV, static solvers pushed desks and chairs into the room's geometric center (`0.50, -0.40`), blocking primary traffic paths and severing sightlines between seating and media displays.
3. **Variant Indistinguishability**: Shifting coordinates by nominal centimeter deltas failed to communicate distinct architectural philosophies to users in 3D previews.

We need a dynamic, parametric spatial solver that computes perimeter-anchored functional zones adapted to arbitrary room dimensions (`room.width`, `room.length`), respects aperture sweep constraints (doors and windows), maintains clear visual sightlines, and generates three distinctly characterized layouts.

## Decision Drivers

* **Parametric Room Adaptation**: Layout positions must derive from bounding perimeters (`-halfW` to `halfW`, `-halfL` to `halfL`) and aperture positions rather than hardcoded magic coordinates.
* **Perimeter Functional Zoning**:
  - **Sleeping Zone**: Beds anchored to stable, quiet perimeter walls away from entrance door sweeps.
  - **Workstation Zone**: Desks anchored against perimeter walls under or adjacent to window daylight apertures, with task chairs paired on the egress side.
  - **Media & Lounge Zone**: Sofas dynamically positioned directly opposite TV consoles along viewing vectors with unobstructed line of sight.
  - **Storage Zone**: Wardrobes flush against corner perimeter walls, with doors opening into open room space.
* **Aperture & Door-Swing Immunity**: Door swing zones ($R = \text{door.width}$) are hard keep-out zones.
* **Panero & Zelnik Verification**: Every layout variant must strictly satisfy zero critical walkway bottlenecks ($\ge 76.2\text{ cm}$), compliant desk pull-back ($\ge 76.2\text{ cm}$), and comfortable bed-making access ($\ge 66\text{ cm}$).
* **Clear Variant Archetypes**: The three variants must provide distinctly contrasting room experiences (e.g. daylight-focused study, open central plaza flow, and quiet acoustic retreat).

## Considered Options

* **Option 1: Hardcoded Point Offsets**: Maintain static coordinate tables with minor conditional branches.
  - *Rejected*: Fails when room dimensions change or openings move.
* **Option 2: Stochastic Monte-Carlo Physics Relaxation**: Simulate 2D rigid-body repulsive physics until forces settle.
  - *Rejected*: Non-deterministic, high CPU cycle overhead, non-instantaneous in UI, and risks settling into un-ergonomic local minima.
* **Option 3: Parametric Perimeter Slotting with Semantic Pairing**:
  - Dynamically partition perimeter walls into candidate slots.
  - Subtract door sweep keep-out zones.
  - Pair TV and Sofa along viewing normal vectors; pair Desk and Chair along daylight/egress vectors.
  - Anchor heavy storage and beds to quiet perimeter quadrants.

## Decision Outcome

Chosen option: **Option 3: Parametric Perimeter Slotting with Semantic Pairing**.

### Architectural Pipeline

```
Room Dimensions (W, L) & Apertures (Doors, Windows)
                      |
                      v
      [1. Perimeter Boundary & Keep-Out Zone]
      - Door swing sweep box: Keep-out zone
      - Window vectors: Daylight attractors
                      |
                      v
      [2. Semantic Functional Pairing]
      - TV ◄──(Unobstructed Viewing Vector)──► Sofa
      - Window ◄── Desk ◄──(Pullback Egress)──► Task Chair
                      |
                      v
      [3. Perimeter Slot Allocation & Variant Archetyping]
      - Circadian Productivity: Daylight desk priority on window wall
      - Open Flow: Expansive central plaza, reoriented bed mass
      - Restful Sanctuary: Quiet zone bed priority, tucked study nook
                      |
                      v
      [4. Panero & Zelnik Clearance Guarantee]
      - Walkway distance >= 76.2 cm
      - Bed side clearance >= 66 cm
      - Door swing clearance 100%
```

## Consequences

* **Positive**:
  - The solver seamlessly adapts to any scanned room size or orientation.
  - No furniture floats awkwardly in the center of the room.
  - Viewing sightlines from sofa to television are guaranteed clear.
  - The three layout variants offer perceptible, meaningful spatial differences.
* **Negative**:
  - Requires coordinate bounds validation to ensure extreme room aspect ratios (e.g., long narrow corridors) degrade gracefully.
