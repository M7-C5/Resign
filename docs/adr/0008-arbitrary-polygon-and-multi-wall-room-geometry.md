# ADR 0008: Arbitrary Polygon and Multi-Wall Room Geometry Engine

* Status: accepted
* Date: 2026-10-21
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign's initial scanning pipeline (ADR 0007) collapsed detected room geometry into a single bounding box cuboid (`roomWidth × roomLength × roomHeight`) with 4 synthetic bounding walls.

While sufficient for simple rectangular bedrooms, real-world residential architecture frequently features non-rectangular layouts:
1. **L-Shaped Rooms**: Common in primary bedrooms with entryway nooks, walk-in corridors, or open-plan living-dining areas.
2. **Polygonal / Angled Rooms**: 5-sided or 6-sided rooms (hexagonal layouts, bay window extensions, chimney breast alcoves, attic bedrooms).
3. **Spatial Clearance Failure**: A naive bounding box creates phantom floor space in L-shaped cutouts, causing [`SpatialClearanceEngine`](docs/ARCHITECTURE.md) to place furniture in physical building voids.
4. **Solar Ephemeris Shadow Inaccuracy**: An oversized rectangular envelope distorts sunlight raycasting and cast shadows, misrepresenting daylight penetration in alcoves.

Apple's RoomPlan framework natively detects individual wall surfaces (`CapturedRoom.walls: [CapturedRoom.Surface]`), each with its own transform matrix, dimensions, and orientation. We must upgrade Resign's spatial pipeline to preserve and render arbitrary multi-wall polygon geometry.

## Decision Drivers

* **Real-World Architectural Accuracy**: Faithfully capture and render L-shaped, polygonal, and alcove rooms without collapsing them into rectangles.
* **Deterministic Sub-Millisecond Triangulation**: Triangulate arbitrary 2D polygon floor boundaries (including concave polygons like L-shapes) without external heavyweight dependencies or native CAD frameworks.
* **Per-Segment Wall Snapping**: Mathematically snap furniture items to their nearest detected physical wall segment regardless of wall angle or room shape.
* **Backward Compatibility & Headless Testability**: Keep domain contracts pure Swift (`Sendable`), allowing automated headless unit testing without requiring physical LiDAR camera hardware.

## Considered Options

1. **Option 1: Rely on Apple's Raw USDZ Export (`capturedRoom.export`)**:
   Use Apple's stock exporter to output a USDZ file.
   * *Rejected*: Apple's raw USDZ output does not support custom architectural PBR shaders (warm oak floor, matte drywall, transparent glass), cannot run in headless unit tests (requires live device/framework objects), and does not expose segmented wall models to downstream layout and solar engines.
2. **Option 2: 2D Bounding-Box Approximation with Alcove Cutouts**:
   Maintain a 2D grid/quadtree of rectangular sub-boxes.
   * *Rejected*: Fails for angled/hexagonal walls (such as $45^\circ$ or $60^\circ$ walls) and introduces complex CSG boolean operations.
3. **Option 3: Segmented Multi-Wall Pipeline with Ear-Clipping Polygon Triangulation**:
   - Model walls as distinct 3D segments (`ScannedWallPayload`) retaining real-world transforms.
   - Assemble perimeter wall segments into an ordered 2D boundary polygon.
   - Triangulate the floor polygon using a pure Swift Ear-Clipping algorithm ($O(n^2)$ for $n$ vertices, sub-millisecond for residential wall counts).
   - Generate OpenUSD (`.usda`) meshes for each wall segment with aperture cutouts, plus the triangulated floor mesh.
   - Snap furniture to the nearest 2D wall segment line.

## Decision Outcome

Chosen option: **Option 3: Segmented Multi-Wall Pipeline with Ear-Clipping Polygon Triangulation**.

### Architectural Specification

1. **Pure Domain Payload (`ScannedWallPayload`)**:
   - Extracted from `capturedRoom.walls`.
   - Stores `id: UUID`, `position: SIMD3<Float>`, `dimensions: SIMD3<Float>` ($X$: length, $Y$: height, $Z$: thickness), `rotationYaw: Float`, and `transform: simd_float4x4`.
   - Exposes computed 2D floor base endpoints (`startPoint` and `endPoint`).

2. **Polygon Triangulator (`PolygonTriangulator`)**:
   - Pure Swift implementation of the Ear-Clipping triangulation algorithm.
   - Handles convex and concave simple polygons (triangles, rectangles, L-shapes, hexagons, octagons).
   - Generates counter-clockwise indexed triangles (`[PolygonTriangle]`) for USD mesh definition.

3. **Multi-Wall Procedural USD Generator (`ProceduralRoomUSDZGenerator`)**:
   - Iterates over `payload.walls` to generate individual `Mesh "Wall_<id>"` prims with local aperture cutouts.
   - If `payload.walls` is empty, gracefully falls back to 4 perimeter walls for backward compatibility.
   - Constructs `Mesh "Floor"` using the ear-clipped triangle index buffer.

4. **Arbitrary Wall Snapping (`RoomCaptureSanitizer`)**:
   - Measures point-to-segment distance from furniture center to each wall segment in the XZ plane.
   - If distance to the nearest wall surface is $\le 15\text{ cm}$ and orientation is within $\pm 15^\circ$ of parallel/perpendicular, snaps the furniture flush against the wall segment and locks yaw alignment.

### Consequences

* Resign accurately represents L-shaped rooms, bay windows, and multi-sided polygonal offices (such as wide hexagons).
* Zero phantom floor space in spatial clearance calculations.
* Sub-second execution with zero external C/C++ or CAD library dependencies.
* Backward compatible with all existing rectangular reference mock assets and tests.
