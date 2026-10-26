# ADR 0021: Calibrate Room North Before Light Placement

- Status: Accepted
- Date: 2026-10-26
- Amends: [ADR 0015](0015-geographic-mock-daylight.md), [ADR 0020](0020-layout-lights-in-room-simulation.md)

## Context

The room's coordinate frame must be aligned with true north before daylight direction can be simulated. `Room.compass` already stores the clockwise true-north bearing of the room's local -Z axis, but there was no user flow to calibrate it or pass it into Studio 3D.

## Decision

Insert a north-alignment step between a completed room scan and artificial-light placement. Core Location supplies the device heading, preferring `trueHeading` and clearly identifying magnetic-north fallback. North locks only when heading accuracy is within 8 degrees and the heading remains within 8 degrees of north for 2 continuous seconds. The screen then keeps the floor plan fixed and lets the user rotate a person marker at the plan center until its arrow points north. The screen does not pan, zoom, or tilt the plan.

If the plan arrow is rotated clockwise by θ from the plan's -Z axis, persist `Room.compass = normalize(-θ)`, the clockwise bearing of the room's -Z axis. Studio 3D passes that value to `SolarSimulationContext.roomHeadingDegrees` so sunlight azimuth is evaluated in the saved room coordinate frame.

The reference room's window remains on its local +X wall. Its geographic bearing is `normalize(Room.compass + 90°)`, and the Lighting Simulation caption derives its cardinal direction from that same saved heading. A 180° room heading therefore makes the window face west: direct sunlight is rejected in the morning and admitted in the afternoon. Diffuse sky illumination remains available during daylight independently of direct incidence. Reopening a saved layout and confirming or discarding time-slider edits preserve this orientation.

Request location authorization only in the orientation step and keep location updates active while the screen is visible, because Core Location needs current location updates to provide `trueHeading`. Stop both location and heading updates after lock or when leaving the screen. If the heading sensor is unavailable, expose a manual heading control; this also makes the flow previewable in Simulator. A denied location permission may fall back to magnetic north and is labeled as such.

The Dashboard retains the dedicated room scanner and review flow from ADR 0019. Scan review navigates to `RoomCreationRoute.orientation(layoutID:)`, which loads the scanned layout and its existing room. Saving north advances to light placement for the same layout; Back returns to scan review. Saving lights dismisses the creation flow, and the selected saved-layout action opens Studio 3D with the saved bearing and fixtures.

## Consequences

No SwiftData schema change is required: the flow uses the existing `Room.compass`, `Room.updatedAt`, and `Layout.room` fields. The saved heading now affects natural-light direction. Magnetic fallback may differ from true north due to local magnetic declination; true heading is preferred whenever Core Location provides it.

## Validation

Unit tests cover the continuous two-second lock, reset when the device leaves the north tolerance, wraparound near 0 degrees, avatar-angle to room-heading conversion, all eight window compass directions, and propagation of a reloaded room heading into the RealityKit beam's morning/afternoon exposure. Night shutdown and confirm/discard orientation preservation are included.
