# ADR 0027: Scanned Room Square Orientation and Centered Origin Normalization

## Context and Problem Statement
When scanning rooms via RoomPlan or loading native parametric USDZ scan assets (such as `Room-2.usdz`), the initial scanning trajectory often introduces an arbitrary yaw tilt (for example, +6.98° / +0.1219 rad in `Room-2.usdz`) relative to the world coordinate frame. Furthermore, the geometric center of the scanned room is offset from the origin (e.g. `X = -1.29m, Z = -0.32m`), and the floor level is translated downwards (e.g. `floorY = -1.218m`).

Previously, loading USDZ rooms directly attached the entity to the root anchor without orientation or translation normalization. This caused three critical architectural and UX failures:
1. **Slanted Room in Viewport**: The entire room appeared rotated counter-clockwise by ~7° and offset to the lower-left corner of the viewport.
2. **Unaligned Furniture & Broken Snap**: Procedural and user furniture placed with world yaw 0° or 90° was visibly misaligned with the drywall boundaries. Furthermore, rotation snapping (which snaps to multiples of 90° in world space) could never align flush against the slanted walls.
3. **Displaced Ceiling Fixtures**: Fixture indicators calculated relative to the room frame rendered outside the offset room boundary.

## Decision Drivers
- Room walls must be squarely aligned with world coordinate axes $X$ (East-West) and $Z$ (North-South) so that 90° and 45° rotation snapping naturally snaps flush to the walls.
- The geometric room centroid must be located at $(0, 0, 0)$ horizontally, and the authentic floor surface must be grounded at $Y = 0.0$.
- Camera target must automatically center on the normalized room origin $(0, 0.8, 0)$.
- The normalization must work automatically for both native parametric RoomPlan USDZ exports and synthetic test harnesses (`MockRoom.usdz`).
- Existing seeded layouts on user devices must seamlessly migrate to the new centered coordinate frame without data corruption or collisions.

## Considered Options
1. **Offset furniture rotation to match the room's slant**: Keep the room tilted and adjust furniture yaw and snap angles by $+6.98^\circ$.
   - *Downside*: Complicates all physics, SAT collision checks, cutaway normal projections, and viewport camera presets with arbitrary room angles.
2. **Container-level orientation and origin normalization**: Wrap the loaded room asset in an intermediate `CaptureSpace` container entity, calculate the dominant wall tilt deviation from parametric wall model matrices, rotate the container by the inverse tilt, and translate the container so the geometric center is at $(0, 0)$ and floor at $Y = 0.0$.
   - *Upside*: Establishes an invariant world coordinate system where world axes match room axes, floor is at 0.0, and 90° snapping is flush to walls.

## Decision Outcome
Chosen Option: **Container-level orientation and origin normalization** (Option 2).

### Architectural Implementation:
1. **Dominant Wall Tilt Extraction**:
   - `RoomSceneController` inspects wall models within `loaded` and extracts their world orientation vectors:
     $$\mathbf{dir} = \mathbf{q} \cdot (1, 0, 0)$$
   - Calculates the angle relative to coordinate axes modulo $\pi / 2$:
     $$\text{diff} = \text{normalizeQuarterTurn}(\text{atan2}(\mathbf{dir}.z, \mathbf{dir}.x))$$
   - Takes the median deviation over all walls (`dominantTilt`) to ensure robust immunity against partial or angled walls.
2. **Container Transform**:
   - Creates a intermediate container `CaptureSpace` holding `loaded`, wrapped within `NormalizedRoom`.
   - Applies the inverse yaw:
     $$\mathbf{orientation} = \text{simd\_quatf}(\text{angle: dominantTilt}, \text{axis: } [0, 1, 0])$$
   - Computes bounds in straightened coordinates and shifts the container:
     $$\mathbf{position} = [-cx, -\text{rawFloorY}, -cz]$$
   - Sets `floorLevel = 0.0` and camera target to $(0, 0.8, 0)$.
3. **Interior Drywall & Cutaway Normal Alignment**:
   - Outward normals for wall cutaways simplify cleanly to $(\pm 1, 0)$ and $(0, \pm 1)$.
   - Interior drywall limits become symmetrically centered (e.g. $X \in [-2.02, 2.02]$, $Z \in [-2.11, 2.11]$).
4. **Seed Furniture Migration**:
   - `DashboardViewModel.ensureRoom2Seeded` detects legacy uncentered furniture (`positionY < -0.5`) and automatically re-seeds with aligned coordinates at $Y = 0.0$, guaranteeing zero collisions and straight placement.

## Consequences
- **Positive**: Viewport presets (Top, Front, Back, Left, Right) frame the room completely straight and centered.
- **Positive**: Furniture rotation and snapping to 90° / 45° align 100% flush with the walls.
- **Positive**: Ceiling light fixtures and window apertures render in authentic alignment inside the room envelope.
- **Negative / Neutral**: Requires existing legacy test expectations on uncentered asymmetric bounds to be updated to centered symmetric intervals.
