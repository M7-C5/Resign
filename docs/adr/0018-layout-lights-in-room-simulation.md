# ADR 0018: Simulate Layout-Saved Light Fixtures

- Status: Accepted
- Date: 2026-10-26
- Amends: [ADR 0011](0011-lightdraft-transient-edit-pattern.md), [ADR 0017](0017-window-shaped-sunlight.md)

## Context

The ceiling-grid flow already saves configured fixtures as `Light` records owned by a `Layout`. Studio 3D previously ignored those records and generated unrelated mock lamps, so saved positions, brightness, color temperature, and on/off state did not affect the simulation.

## Decision

Dashboard routes a layout into Studio 3D by its stable identifier. Studio 3D reads only that layout's `Light` relationship and converts each model into a transient `RoomLightingFixture` value before passing it to the RealityKit rig. If no layout is selected, previews retain their built-in sample fixtures; a selected layout with no saved lights has no artificial fixtures.

Map grid columns and rows 0–4 to centered room-space X and Z positions at 0.65-meter spacing. Map `elevationZ` to RealityKit's Y axis, and preserve each record's lumens, Kelvin temperature, and `isOn` value. The simulation's artificial-light switch acts as a session-only master switch over the saved per-fixture state. Natural sunlight remains independent.

The Dashboard's create action creates a `Layout`, opens the existing light-placement flow, and continues to Studio 3D with that same layout after saving. Returning before saving removes the newly created empty layout. Existing layouts can be opened directly in their own lighting simulation.

## Consequences

No SwiftData schema changes are required. Layouts now isolate their fixture sets in the simulation. Grid-to-room mapping remains a mock-room convention and assumes the 5×5 grid spans 2.6 meters; a future measured-room renderer must replace that mapping with room dimensions.

## Validation

Unit tests verify grid-to-room coordinate conversion, fixture property preservation, master-switch behavior, per-fixture off state, and that a selected empty layout does not receive preview lamps. Fast verification covers compilation and the unit test plan.
