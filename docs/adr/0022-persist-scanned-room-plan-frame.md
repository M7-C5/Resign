# ADR 0022: Persist the Scanned Room Plan Frame

- Status: Accepted
- Date: 2026-10-27
- Amends: [ADR 0007](0007-roomplan-capture-and-sanitizer-pipeline.md), [ADR 0021](0021-room-north-alignment.md)

## Context

RoomPlan furniture and openings are captured in a camera-relative 3D frame. The orientation screen previously plotted those world X/Z values directly inside a rectangular room outline. A rotated or offset scan therefore showed furniture and openings in the wrong positions, making it difficult to identify which scanned wall corresponds to north.

## Decision Drivers

- Keep the north-selection plan aligned with the same walls and objects the user just scanned.
- Preserve a stable local coordinate frame for furniture and openings without changing their 3D positions.
- Keep already-saved rooms readable when they lack scan-frame metadata.

## Considered Options

1. **Continue plotting raw camera coordinates**: Rejected because rotated and offset rooms appear misplaced.
2. **Render the imported USDZ as the plan**: Rejected because it would require a separate top-down camera and make the centered avatar interaction harder to control consistently.
3. **Persist a compact scan-local projection**: Chosen because it reuses RoomPlan wall transforms and supports the existing 2D avatar interaction.

## Decision Outcome

Persist a compact, optional `RoomPlanSnapshot` with each new scan. It contains the world-space scan center, the dominant wall yaw, optional floor height, and captured wall segments projected into that room-local frame. The orientation plan uses this same frame to transform furniture, doors, and windows before drawing them.

Store the encoded snapshot in the optional `Room.planSnapshotData` SwiftData attribute. Rooms created before this field exists remain valid and use a rectangular dimensions fallback. Keep the snapshot limited to orientation and plan rendering; it does not replace the USDZ asset or alter the lighting simulation's room coordinate contract.

## Consequences

- The compass marker is positioned at the center of the scanned room, and detected furniture and openings line up with the scanned wall segments.
- The schema change is additive and optional; no coordinated migration is required.
- The plan traces captured wall segments over a neutral background. It does not retain a triangulated floor polygon.
- Room-local north remains the user's saved `Room.compass` bearing from ADR 0021; the raw scan yaw is used only to project geometry into the 2D plan.
