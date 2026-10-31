# ADR 0033: Inspect the Room Independently of Lighting Simulation

- Status: Accepted
- Date: 2026-10-29
- Amends: [ADR 0023](0023-render-selected-scanned-layout-lighting.md), [ADR 0032](0032-adaptive-lighting-workspaces.md)

## Context

The lighting preview always displayed generated spherical lamp markers and simulated illumination. Users also need to inspect furniture placement and room geometry without a dark nighttime preview or lighting markers obscuring the layout.

## Decision Drivers

- Show the same selected room with neutral, consistent visibility.
- Hide generated lamp markers and disable simulated sun, sky, and artificial lights together.
- Preserve fixture records, material appearance, camera state, and saved lighting choices.
- Default to a clear neutral layout, with an explicit session-only simulation On/Off button.

## Considered Options

1. Hide lamp markers alone: rejected because the room could remain dark or tinted by simulation.
2. Add a layout-only mode that restores neutral environment illumination and disables the lighting rig: chosen.

## Decision Outcome

Add a session-only preview mode to lighting settings. The studio starts in Layout Only and provides an icon-only lightbulb button directly on the preview, with a Light Simulation accessibility label. Turning it on immediately activates simulation and opens the compact sheet or iPad inspector; a separate settings button reopens controls while active. Turning it off closes controls, discards pending time/lamp edits, and returns to Layout Only. Layout Only disables the complete generated lighting rig, including its spherical markers, and restores default environment illumination at a fixed exposure. Remove the simulation-specific image-based-light overrides so the room receives neutral ambient illumination. The fixed architectural key/fill lights from the interactive studio are enabled only in the neutral layout; disable them during lighting simulation so they cannot wash out sun/lamp changes. Do not replace materials, reload geometry, move the camera, or alter saved fixtures.

Return to Lighting by restoring environment suppression and reapplying retained time and artificial-light settings. The main button takes effect immediately and is independent of Confirm/Cancel for time and lamp edits; cancelling controls leaves simulation on until the user switches it off. Show controls only during simulation. No SwiftData schema or persistence changes are introduced.

## Consequences

- The room stays visible at night without visible generated lighting spheres.
- Neutral environmental shading preserves furniture colors and material textures; this is an inspection view rather than a photometric result.
- Fixture updates and asynchronous room loading retain the active mode.

## Validation

Unit tests cover neutral startup, explicit activation/deactivation, preservation of confirmed choices, discard of pending changes when switching off, rig visibility, time-independent neutral exposure, environment restoration, camera preservation, draft confirmation/discard, asynchronous loading, and fixture updates. Run `./scripts/verify.sh`; manually compare both modes in the compact sheet and iPad inspector.
