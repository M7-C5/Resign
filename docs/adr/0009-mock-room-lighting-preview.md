# ADR 0009: Mock Room Lighting Preview

- Status: accepted
- Date: 2026-10-22

## Decision

Extend the session contract in ADR 0008 with a live SceneKit preview of the bundled MockRoom. While the modal is open, render draft settings; otherwise render confirmed settings. Cancel and interactive dismissal restore confirmed lighting. No SwiftData writes occur.

Daylight follows an illustrative sine curve from 06.00 to 18.00, peaking at noon. Ambient illumination retains a small nighttime baseline. Two warm ceiling spotlights represent sample artificial fixtures; the toggle controls both. These are not the configured LightingSetup fixtures and do not represent calibrated lux or geographic solar simulation.

The preview hides the ceiling and south/west walls plus the entry door to show the interior from a southwest camera. The USDZ asset remains unchanged. Camera orbit and zoom are enabled. Updating controls changes light properties without reloading the room or resetting the camera.

## Scope

The studio can be exercised in its Xcode preview. App navigation integration, real light-source mapping, and physical sunlight simulation remain outside this iteration. ADR 0008's UI-only renderer limitation is superseded; session-only persistence remains unchanged.

## Validation

Unit tests cover daylight boundaries, artificial-light independence, live draft selection, confirm, and rollback. Build and fast unit verification are required.
