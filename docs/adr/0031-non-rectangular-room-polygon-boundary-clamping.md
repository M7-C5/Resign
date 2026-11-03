# ADR 0031: Non-Rectangular Room Polygon Boundary Clamping and Full Envelope Traversal

## Context and Problem Statement
When arranging furniture in 3D Studio (`Studio3DView` / `Studio3DViewModel`), furniture movement on the floor plane was previously constrained by `SpatialClearanceEngine.clampToRoomBoundaries` using an axis-aligned bounding box `(minX, maxX, minZ, maxZ)`.

In rooms with non-rectangular footprints (such as L-shaped rooms, T-shaped spaces, alcoves, grooved corridors, or rooms with structural wall notches):
1. **Collapsed Interior Bounds**: In `RoomSceneController.load()`, wall candidate coordinates were evaluated by taking `min` on the positive axis and `max` on the negative axis (`interiorMaxX = min(interiorMaxX, b.min.x)`). In any room with a reflex corner (such as the interior notch of an L-shape), this collapsed the bounding box to the smallest inner rectangular sub-volume, completely cutting off the room's extended wings.
2. **Nominal Dimension Clamping**: In `loadScannedLayout`, `roomHorizontalBounds` was initialized from symmetric nominal dimensions `(-width/2 ... width/2, -length/2 ... length/2)`. For non-square or offset rooms, furniture was artificially trapped within a central square and blocked from entering the tail of the L.
3. **No Polygon Awareness**: `SpatialClearanceEngine` lacked point-in-polygon testing against scanned wall segments (`RoomPlanSnapshot.WallSegment`), making it impossible to navigate concave floor plans without either clipping through walls or hitting invisible artificial barriers.

## Decision Drivers
- **Full Floor Plan Traversal**: Homeowners and designers must be able to drag furniture into any valid interior area of their room, including the tail of an L, alcoves, nooks, and irregular wall grooves.
- **Physical Barrier Enforcement**: Furniture must not escape through exterior wall segments into empty outer voids or exterior notches.
- **Sub-Millisecond Drag Responsiveness**: Collision and boundary checks run during continuous touch drag gestures at 60/120 FPS and must remain sub-millisecond without stutter.

## Considered Options
1. **Unbounded Dragging with Post-Placement Warning**: Allow furniture to be dragged anywhere without clamping, flagging red collision highlights when outside.
   - *Downside*: Poor ergonomics; furniture easily flies outside the room mesh into the void during quick touch drags.
2. **Axis-Aligned Bounding Box Only (Enlarged)**: Expand the bounding box to the union envelope of all walls without polygon checking.
   - *Downside*: Furniture can be dragged into the empty exterior notch of an L-shaped room where no floor or ceiling exists.
3. **Dual-Stage Full-Envelope Clamping with Polygon Projection**:
   - Stage 1: Clamp candidate $(X, Z)$ to the room's full outer bounding envelope derived from `RoomPlanBounds` (the union of all wall segment coordinates).
   - Stage 2: If wall segments are present, evaluate whether the clamped point is inside the room polygon using 2D ray-casting. If outside (e.g. dragged into the exterior notch of an L-shape), project to the closest interior point along the nearest wall segment.
   - *Upside*: Supports arbitrary room shapes (L-shape, T-shape, U-shape, grooved alcoves) with natural wall boundary resistance, zero invisible barriers inside valid room wings, and sub-millisecond execution.

## Decision Outcome
Chosen Option: **Option 3 (Dual-Stage Full-Envelope Clamping with Polygon Projection)**.

### Architectural Pipeline

```mermaid
flowchart TD
    TouchDrag[User Drag Gesture: floorPos (X, Z)] --> FullBox["Stage 1: Clamp to Full Envelope [minX, maxX] x [minZ, maxZ] (RoomPlanBounds)"]
    FullBox --> PolygonCheck{"Stage 2: Point in Polygon? (Ray-Casting against wallSegments)"}
    
    PolygonCheck -->|Inside Room Polygon| AllowMove["Move Furniture to Clamped (X, Z)"]
    PolygonCheck -->|Outside in Notch/Void| Project["Project to Closest Wall Segment + Interior Margin"]
    Project --> AllowMove
```

### Key Implementation Details:
1. **`SpatialClearanceEngine.clampToRoomBoundaries`**:
   - Added polygon-aware overload taking `walls: [RoomPlanSnapshot.WallSegment]`.
   - Uses `isPointInsidePolygon` (ray-casting crossing test) and `projectIntoRoomPolygon` (perpendicular projection onto closest wall segment offset by wall margin).
2. **`RoomSceneController.load` & `loadScannedLayout`**:
   - `roomHorizontalBounds` now resolves to the full outer envelope covering all wall segments via `RoomPlanBounds` and `centeredBounds`, never collapsing to the inner notch.
   - Exposes `roomWallSegments: [RoomPlanSnapshot.WallSegment]` to the view model.
3. **`Studio3DViewModel.moveSelectedFurniture`**:
   - Passes `roomWallSegments` into `SpatialClearanceEngine.clampToRoomBoundaries`, allowing furniture to move freely into all room wings while preventing penetration into exterior notches.

## Consequences

### Positive
- **Natural L-Shaped Navigation**: Users can move furniture into the tail of L-shaped rooms, alcoves, and irregular floor plans without hitting invisible square walls.
- **Exterior Notch Protection**: Furniture dragged towards the outside corner of an L-shape slides naturally along the wall rather than falling into the void.
- **Backward Compatibility**: Fully compatible with existing rectangular rooms and legacy mock reference environments.

### Negative / Trade-Offs
- For highly self-intersecting or non-manifold LiDAR wall scans (rare corrupted scans), ray-casting may fall back to the outer bounding box.
