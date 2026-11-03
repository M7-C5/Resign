# ADR 0026: Viewport Snapping and Dynamic Wall Cutaways

## Status
Accepted

## Context
When inspecting and rearranging furniture in 3D Studio, users frequently require standard architectural vantage points (Top, Front, Back, Left, Right, and Reset/Dollhouse) to verify wall clearance, door clearances, and aligned sightlines. Without preset camera snapping, positioning the orbit camera to an exact orthogonal angle is tedious.

Furthermore, when the camera is lowered to eye-level or orthogonal side angles (pitch $\sim 0^\circ\text{--}10^\circ$), the perimeter walls standing between the viewer and the interior obstruct the view, hiding furniture inside the room. In architectural design software and isometric games (e.g., The Sims), exterior walls facing the screen dynamically cut away to maintain an open, unobstructed cross-section.

## Decision Drivers
1. **Ergonomic Viewport Snapping**: Provide immediate, accessible snapping to standard architectural angles (Top bird's-eye view, orthogonal Front/Back/Left/Right elevations, and dollhouse isometric reset) via a single 44pt control beside the lighting button.
2. **Smooth Spatial Continuity**: Animated ease-in-out camera transitions (~0.35s) preserve user orientation and depth perception rather than disorienting jump-cuts.
3. **Sims-Style Dynamic Cutaway**: Up to 2 perimeter walls facing the screen ($\mathbf{n}_{\text{wall}} \cdot \mathbf{d}_{\text{cam}} > 0.1$) must automatically hide (`isEnabled = false`) at side angles (pitch $< 60^\circ$) to reveal interior contents.
4. **Top View Boundary Preservation**: High-angle bird's-eye view ($\ge 60^\circ$) must keep all 4 perimeter walls visible to preserve the room boundary frame.
5. **Aperture & Frame Integrity**: Window and door frames attached to a cutaway wall must hide with that wall to avoid floating mid-air.
6. **Zero Performance Overhead**: Normal vector dot product evaluation executes synchronously within the orbit loop without physics raycasting or render passes.

## Considered Options
1. **Static Presets Only (No Cutaways)**: Snap camera to angles, but leave all walls solid.
   - *Downside*: Orthogonal side views look directly into exterior plaster, completely blocking furniture.
2. **Translucent/Ghosted Wall Meshes**: Alter wall material opacity to ~15%.
   - *Downside*: RealityKit PBR depth sorting with transparency creates visual artifacts and shadow anomalies; does not provide the clean, crisp cross-section users expect.
3. **Dynamic Continuous Cutaway with Viewport Snapping Menu (Chosen)**:
   - Provide a top-right `Menu` triggered by `cube.plane.bottom.right.detached`.
   - Calculate horizontal camera direction $\mathbf{d}_{\text{cam}} = (\sin(\text{yaw}), \cos(\text{yaw}))$.
   - Hide up to 2 walls with positive dot products against the camera direction when pitch $< 60^\circ$.

## Decision Outcome
Adopt Option 3.

### Implementation Details:
1. **`ViewportPreset` Domain Enum**:
   Defines `.top`, `.front`, `.back`, `.left`, `.right`, and `.dollhouse` with target yaw, pitch, and SF Symbols.
2. **`RoomSceneController.snapToViewport`**:
   Interpolates camera yaw and pitch over 0.35s with an ease-in-out curve.
3. **`WallCutawayItem` Registry**:
   Maintains references to wall entities and horizontal outward normal vectors ($\mathbf{n} \in \mathbb{R}^2$) for both USDZ room shells (`Arch_grp`) and parametric reconstructed shells (`ScannedApertureWalls`).
4. **`RoomSceneController.updateWallCutaways()`**:
   Evaluated continuously during both animated snapping and touch orbit gestures.

## Consequences
### Positive:
- Instant one-tap navigation to Top-down floorplan, Front, Back, Left, Right, and Dollhouse angles.
- Interior furniture is never occluded by foreground drywall.
- Sub-second verification tests run cleanly without RealityKit rendering dependencies.

### Negative / Trade-offs:
- Rooms with non-rectangular angled walls require accurate normal classification from wall endpoints.
