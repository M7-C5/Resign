# ADR 0007: Panero & Zelnik Spatial Diagnostics, AI Reasoning Pipeline, and Layout Solver Integration

* Status: accepted
* Date: 2026-10-21
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign aims to provide interior spatial optimization grounded in authentic ergonomic principles. Human ergonomics and spatial clearances are mathematically governed by Julius Panero & Martin Zelnik's seminal standard (*Human Dimension & Interior Space*), covering critical circulation thresholds, bed-making clearances, desk pull-backs, and door swing arcs.

When bridging scanned room spatial data with Large Language Models (LLMs) and downstream layout engines, two failure modes must be avoided:
1. **LLM Spatial Hallucination**: LLMs struggle with precise 3D collision geometry, Euclidean distances, and vector coordinates, resulting in invalid layouts or geometric drift.
2. **Scene Breakage via Invalid IDs**: LLMs can hallucinate entity identifiers or references, breaking RealityKit 3D scene graphs and SwiftData relationships.

We need a clear architectural contract that extracts room geometry, evaluates rulebook clearances deterministically in Swift, formats compact DTOs for the LLM, sanitizes LLM reasoning and solver configurations, and feeds valid solver parameters into the layout optimization engine.

## Decision Drivers

* **Strict Boundary of Concerns**: Swift deterministic engines handle geometry, collision bounding boxes, and metric clearances; LLMs handle qualitative reasoning, ergonomic explanations, and solver parameterization.
* **Panero & Zelnik Standardization**: Strict adherence to published metric thresholds:
  - Walkways: Minimum 76.2 cm (critical, `R1`), 91.4 cm (recommended, `R2`).
  - Desk rear clearance: Minimum 76.2 cm (`R3`) for chair pull-back and seated egress.
  - Bed operational zone: 66–99 cm (`R4`) for bed-making, 116–157 cm (`R5`) for under-bed storage.
  - Door swing: 100% unobstructed (`R6`).
* **Zero 3D Scene Breakage**: Robust validation guarantees that every UUID returned by the LLM exists in the active room before triggering 3D highlight rings or solver constraints.
* **Sub-Second Fast Testability**: Algorithms and prompt builders must be isolated, pure, and testable in memory without requiring remote network calls or GPU rendering.

## Considered Options

* **Option 1: End-to-End LLM Layout Synthesis**: Send raw coordinates to the LLM and ask it to output new 3D coordinates directly.
  - *Rejected*: Prone to severe bounding box intersections, non-physical floating items, and high token latency.
* **Option 2: Pure Hardcoded Heuristics Without AI**: Run local rule checks and apply fixed template offsets.
  - *Rejected*: Lacks contextual human reasoning, user preference adaptation, and dynamic solver weighting.
* **Option 3: Hybrid Deterministic Clearance Detection + AI Reasoning + Layout Solver**:
  - Deterministic `SpatialClearanceEngine` measures physical clearances and flags rule violations.
  - Compact prompt builder packages rounded centimeter data and detected violations.
  - AI reasoning generates human-readable insights (citing rule IDs) and solver settings (pins, must-haves, goal weights).
  - Sanitization layer validates IDs against active scene.
  - `LayoutOptimizerEngine` generates 3 layout variants (Circadian Productivity, Open Flow, Restful Sanctuary).
  - 3D view (`Studio3DViewModel`) renders highlight rings on clashing furniture IDs.

## Decision Outcome

Chosen option: **Option 3: Hybrid Deterministic Clearance Detection + AI Reasoning + Layout Solver**.

### Architecture & Data Flow

```
[Room & Layout (SwiftData)]
        |
        v
[SpatialClearanceEngine]  <-- Panero & Zelnik Rules (R1 - R6)
        |
        v  (Detected Violations: cm & item IDs)
[RoomDiagnosticPromptBuilder]  <-- User Preference
        |
        v  (Compact Centimeter Payload)
[AIDiagnosticService]
        |
        v  (Insights + Solver Settings)
[AIDiagnosticValidator]  <-- Active Furniture IDs (Drop hallucinations)
        |
        +-----------------------------------> [Studio3DViewModel] (Highlight Rings)
        |
        v  (Validated Pins, Must-haves, Weights)
[LayoutOptimizerEngine]
        |
        v
[3 Layout Variants: Circadian / Open Flow / Sanctuary]
```

### Consequences

#### Positive Consequences
* The LLM operates strictly in its strength zone (semantic reasoning, human explanations, preference interpretation, solver goal weighting).
* 3D RealityKit views remain perfectly stable because hallucinated furniture IDs are filtered out before reaching scene state.
* Unit test coverage can verify clearance math, prompt construction, validation sanitization, and layout generation deterministically in milliseconds.
* The 3D view receives clean sets of `UUID`s to project interactive visual highlight rings around clashing items.

#### Negative Consequences
* Requires maintaining explicit Swift representations of bounding boxes and swing arcs in the clearance engine.
