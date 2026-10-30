# ADR 0010: Structured Room Preferences and Grounded Dynamic Layout Insights

* Status: accepted
* Date: 2026-10-26
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

The onboarding step "What's Not Working in Your Room?" collects **problem keyword chips** (e.g. *No privacy*, *Feels cramped*) plus an optional **free-text description** (max 1000 characters). Previously the AI pipeline accepted a single free-form `String` preference, and suggested layouts shipped with hard-coded insight text (including fabricated clearance numbers).

The Layout Suggestions screen shows a dynamic set of insight cards (*Spacious circulation*, *Defined zones*, *Good natural light*, *Easy access*, ...). The count is not fixed at four.

## Decision Drivers

* The AI must receive the user's problems as structured, auditable input.
* On-device LLM output must never assert facts the geometry engine has not verified.
* Free text is untrusted user input (prompt injection surface).
* Everything must work without Apple Intelligence (simulator, CI).

## Decision Outcome

1. **`RoomPreference`** is the single domain contract: selected `ProblemKeyword`s plus sanitized free text. Free text is trimmed, clamped to 1000 characters, and mined for implied problems (`inferredKeywords`). String literals convert to free text for source compatibility.
2. Each keyword maps deterministically to:
   * solver **goal weight** nudges (`suggestedGoalWeights`, used as an anchor in the prompt and by the rulebook),
   * related **insight categories** (ranking priority),
   * a **layout variant affinity**, so the best-fit variant is shown first.
3. **Grounded insights**: `LayoutInsightEngine` computes geometry-backed *candidate* insights per variant (circulation, zoning, natural light, access, privacy, storage) from measured violations and distances. The LLM may only rephrase, prioritise, and drop candidates. `LayoutInsightValidator` rejects invented categories, forces the verified sentiment, clamps text length, de-duplicates per category, and falls back to the deterministic ranking when output is unusable.
4. **Dynamic count**: 0...`LayoutInsightEngine.maxInsights` (6) cards depending on which facts apply.
5. **Result-page diagnostics** (`AIDiagnosticInsight`) gain a short `title` ("Narrow", "Desk", "Window") and a `severity` (`warning`/`critical`) to match the review card design.
6. The free text reaches the model only as a JSON-encoded, quoted field explicitly labelled untrusted data.
7. **Studio 3D Spatial Highlight Aesthetic**: Violation overlays in RealityKit are rendered as clean, simple outlined perimeter shapes with delicate translucent interior fill (`opacity: 0.14`), preserving room floor visibility while delineating the operational clearance envelope. Each rule category receives a distinct, harmonious accent color (`R1` Coral Red, `R2` Warm Amber, `R3` Electric Cobalt Blue, `R4` Mint Green, `R5` Cyan, `R6` Royal Purple), paired with matching color badges in the HUD legend and eye-level floating 3D beacons so users can instantly identify each violation without confusion.
8. **Three-Screen Spatial Redesign Journey**: The user experience is structured into three connected screens:
   * **Preference Page (`PreferencePageView`)**: Collects problem keyword chips (with "See more" disclosure) and free text with character counter.
   * **Your Layout Insights (`YourLayoutResultView`)**: Embedded 3D isometric room with dimension callouts (`5.2 m` × `4.8 m`), outlined clearance envelopes with contextual 90° door swing arc, and the "Room" review points card.
   * **Layout Suggestions (`LayoutSuggestionsDisplayView`)**: 3D view of the selected layout option, dynamic 2x2 grid of insight cards (circulation, zoning, natural light, access), layout variants thumbnail carousel, and blue checkmark layout selection.
9. **Parametric Room-Aware Solver**: Replaced hardcoded static furniture coordinates with a dynamic geometry solver in `LayoutOptimizerEngine`. Positions are computed parametrically from `room.width`, `room.length`, window daylight vectors, and door swing clearance envelopes (`resolveDoorSwingConflicts`), adapting cleanly to arbitrary room sizes. Removed all hardcoded placeholder `layout.insights` arrays so insights are exclusively driven by `LayoutInsightEngine`.

### Pipeline

```
RoomPreference (chips + free text)
   ├─► suggestedGoalWeights ─► AIDiagnosticService ─► SolverSettings ─► LayoutOptimizerEngine ─► 3 variants
   ├─► preferredVariantName ─► variant ordering (best fit first)
   └─► focusCategories ─► LayoutInsightEngine.candidates ─► (LLM rephrase) ─► LayoutInsightValidator ─► cards
```

## Consequences

### Positive
* Insights are truthful by construction and personalised to the user's stated problems.
* Fully testable without a model: engine, ranking, validator, and weights are pure.

### Negative / Follow-ups
* Free-text inference uses English phrases only; the LLM covers other languages but the deterministic fallback will not.
* One model call per variant (3 sequential calls) adds latency on device; batch or parallelise if profiling shows a problem.
* Distance thresholds (250 cm daylight, 150 cm zoning, ...) are heuristics and should be tuned with real rooms.
