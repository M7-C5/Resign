# ADR 0045: Manual Light Placement on Uncertain Room Outlines

- Status: Accepted
- Date: 2026-11-03
- Amends: [ADR 0024](0024-adaptive-ceiling-light-placement.md), [ADR 0034](0034-aperture-aware-ceiling-outline.md), [ADR 0035](0035-ceiling-perimeter-and-interior-walls.md)

## Context

RoomPlan can finish a scan while its captured wall segments remain too noisy or fragmented to prove a single closed perimeter. Rejecting all candidate points prevents users from configuring lights even when the visible room plan is sufficient for manual placement.

## Decision

Keep verified-perimeter placement constrained to the reconstructed polygon and its wall-clearance rules. When perimeter validation fails, generate a manual placement lattice within the available plan bounds, keep the points interactive, and display an uncertainty notice that asks users to choose points inside the visible room. Do not treat that fallback lattice as recovered room geometry or as evidence that every point lies inside a concave room. The notice must not intercept taps.

Keep saved-light editing available in either mode. The north arrow is shown as calibrated only when the saved room snapshot contains a north calibration record; otherwise label its direction unknown.

## Consequences

Users can configure lighting without rescanning solely to satisfy outline validation. In uncertain mode, the plan supplies visual guidance and the user chooses valid interior points. Verified scans retain automatic polygon filtering, including concave boundaries and interior-wall clearance.

## Validation

Unit tests verify that uncertain outlines still yield manual placement points and remain marked unverified, while complete concave boundaries continue to exclude outside areas. North-arrow rotation tests verify the inverse relationship between room bearing and plan rotation. Run `./scripts/verify.sh` for the simulator build and isolated unit tests.
