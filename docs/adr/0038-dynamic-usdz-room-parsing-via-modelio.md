# ADR 0038: Dynamic USDZ Room Ingestion via ModelIO Framework

* Status: accepted
* Date: 2026-10-21
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign previously utilized hardcoded presets in `RoomRepository` to represent the reference environment. To guarantee that spatial heuristics, Panero & Zelnik clearances, and AI diagnostic prompts operate on authentic 3D geometry rather than decoupled mock numbers, the application must dynamically parse bundled or user-provided USDZ files (specifically `MockRoom.usdz`) at runtime.

We must dynamically extract room spatial boundaries, openings (doors, windows), and furniture placements from the USDZ scene graph using Apple's headless `ModelIO` (`MDLAsset`) framework before feeding the room situation to the LLM.

## Decision Drivers

* **Authentic 3D Extraction**: Direct extraction of positions, bounding box dimensions, and aperture metrics from `MDLAsset` scene primitives.
* **Zero Hardcoded Drift**: Ensures updates to `MockRoom.usdz` (or future user RoomPlan scans) automatically propagate to spatial clearance analysis and LLM prompt generation without manual code updates.
* **Sub-Second Headless Parsing**: `ModelIO` must inspect meshes without requiring a live `RealityView` or GPU context so it can run headlessly inside unit tests and background services.

## Considered Options

* **Option 1: Hardcoded Mirroring (Status Quo)**: Manually keep Swift structs in sync with USD geometry.
  - *Rejected*: Prone to drift whenever USD assets are modified or when real RoomPlan scans are imported.
* **Option 2: Dynamic ModelIO Parser (`USDZRoomLoader`)**:
  - Recursively traverses `MDLAsset` nodes.
  - Unions child mesh bounding boxes (`MDLAxisAlignedBoundingBox`) to calculate true world-space centroids and extents.
  - Maps structure (`Floor`, `Wall`), openings (`Window`, `Door`), and furniture (`Bed`, `Desk`, `Chair`, `Sofa`, `Closet`, `TV`) directly into SwiftData `Room`, `RoomOpening`, and `Furniture` models.

## Decision Outcome

Chosen option: **Option 2: Dynamic ModelIO Parser (`USDZRoomLoader`)**.

### Consequences

#### Positive Consequences
* The LLM prompt and Panero & Zelnik clearance engine receive real measured geometry directly from the USDZ file.
* Compatible with both bundled reference assets (`MockRoom.usdz`) and exported RoomPlan LiDAR captures.
* Verified via sub-second unit tests in `ResignTests`.

#### Negative Consequences
* Requires `ModelIO` framework import and managing bounding box coordinate systems ($X$-width, $Y$-height, $Z$-depth).
