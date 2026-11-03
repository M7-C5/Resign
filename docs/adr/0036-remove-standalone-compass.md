# ADR 0036: Remove the Standalone Compass from Room Creation

- Status: Accepted
- Date: 2026-10-30
- Supersedes: the compass screen and manual north-marker workflow in [ADR 0021](0021-room-north-alignment.md)

## Context

North will be established as part of room scanning in a future change. Room creation no longer needs a separate compass screen, sensor calibration hold, or draggable north marker between scan review and lighting configuration.

## Decision

Remove the orientation route, screen, sensor reader, ViewModel, calibration-hold logic and their dedicated tests. The scan review's Configure Lighting action opens lighting for the same saved layout directly; Back returns to scan review. Remove the orientation container and rename its continuation callback to describe lighting.

Keep the existing room-plan drawing used by lighting, relocating it into the lighting feature and removing its unused north-marker bindings and gestures. Preserve its wall, opening, furniture and coordinate rendering. Retain the pure angle conversion helpers needed by saved room bearings and lighting simulation.

Keep stored room bearings, persistence attributes and lighting calculations intact. This change does not implement automatic scan-time north capture or change existing scan data. Scanning, inventory, furniture manipulation and build configuration are outside this removal.

## Consequences

The creation flow is scan, review, then lighting, with no compass loading or manual north-alignment step. Existing room bearings continue to drive lighting. New scans use the scan pipeline's current bearing value until scan-time north capture is implemented separately.

## Validation

Update navigation tests for direct scan-review-to-lighting transitions and Back behavior. Retain lighting workspace, saved-bearing and simulation regression tests. Run `./scripts/verify.sh` for compilation and isolated unit tests, then audit the diff for unrelated changes.
