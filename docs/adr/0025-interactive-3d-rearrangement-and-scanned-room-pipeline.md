# ADR 0025: Interactive 3D Room Rearrangement and Scanned Room Pipeline

- Status: Accepted
- Date: 2026-10-28
- Amends: [ADR 0003](0003-room-rearrangement-and-lighting-architecture.md), [ADR 0010](0010-hybrid-native-parametric-room-and-sanitized-furniture.md), [ADR 0018](0018-dashboard-persistence-and-navigation-architecture.md)

## Context

Studio 3D previously rendered a hardcoded `MockRoom.usdz` environment primarily for lighting simulation. When users open a scanned room layout from the Dashboard or scan completion flow, Studio 3D must render the authentic scanned room shell and its detected furniture, rather than falling back to a synthetic mock room. Furthermore, users require Sims-style touch ergonomics to rearrange furniture items in 3D: selecting pieces, translating them along the floor plane ($Y = 0$), rotating them in 90° architectural increments, and preventing boundary clipping or unrealistic collisions, while allowing chairs to nest naturally under desks and dining tables.

## Decision

1. **Scanned Room Ingestion & Zero Mock Fallback**:
   - `RoomSceneController` loads the layout's captured parametric room shell directly from `layout.usdzURL` (exported during RoomPlan capture).
   - In accordance with ADR 0010, crude wireframe `Object_grp` bounding boxes are disabled in the room shell entity, preserving watertight CAD-grade walls, openings, and floors.
   - Furniture entities are instantiated dynamically via `FurnitureEntityFactory` from `layout.furnitures` and attached to the scene anchor with `CollisionComponent` and `InputTargetComponent`.
   - **Zero Mock Fallback**: If `layout.usdzURL` is missing or fails to load, `RoomSceneController` enters the `.failed` state. Studio 3D presents a dedicated "Unable to load scanned room" error state with an explicit "Try Again" reload action and navigation back to scanning. The scene never silently falls back to `MockRoom.usdz`.

2. **Centering & Dynamic Framing**:
   - The camera orbit target dynamically centers on the room centroid $\left[0, \frac{\text{room.height}}{2}, 0\right]$ instead of a fixed coordinate.
   - Camera distance auto-scales based on $\max(\text{room.length}, \text{room.width}) \times 1.8$, ensuring consistent framing across room sizes.

3. **Touch Triage & Sims-Style Rearrangement Ergonomics**:
   - **Touch Triage**: If a drag gesture begins on a furniture entity, it enters **Furniture Translation Mode** and preserves the touch grab offset ($P_{\text{furniture}} - P_{\text{finger}}$) to prevent position jumping. If dragging begins on empty floor or background space, it enters **Camera Orbit Mode**.
   - **Authentic Floor-Level Raycasting**: The raycast intersection dynamically projects onto the authentic USDZ floor plane (`floorLevel` $\approx -1.22\,\text{m}$ in RoomPlan captures like `Room-2.usdz`) rather than the arbitrary world origin $Y = 0$, eliminating parallax displacement and drift between south and north walls.
   - **Permissive Floor Dragging**: Dragging translates the selected piece freely on the horizontal plane within the drywall perimeter boundaries $[X_{\min}, X_{\max}] \times [Z_{\min}, Z_{\max}]$. Objects are NOT hard-locked when passing through obstacles during drag, allowing free motion across cluttered rooms.
   - **Visual Collision Status Gate (Red Status)**:
     - When an item overlaps an incompatible obstacle or exceeds tuck-in depth, its ground-plane halo immediately turns **RED**, and the bottom action bar displays an *"Overlapping with furniture"* alert.
     - While in a colliding state, saving to SwiftData is strictly blocked.
     - Tapping the action button while colliding triggers an undo / revert action back to the last valid collision-free coordinate.
     - Once placed in a valid, collision-free position, the halo returns to **BLUE**, and coordinates are automatically persisted to SwiftData.
   - **Category-Aware Collision & Tuck-In Allowance**:
     - Rigid furniture pairs (e.g., bed $\leftrightarrow$ wardrobe, sofa $\leftrightarrow$ desk) evaluate 2D Separating Axis Theorem (SAT) bounding overlap.
     - Chair-to-table/desk pairs (`chair` $\leftrightarrow$ `desk`, `chair` $\leftrightarrow$ `table`) permit up to 65% overlap depth, allowing chairs to slide naturally into knee-wells and under aprons.
     - Vertically stacked items (e.g. televisions on credenzas) evaluate vertical separation $[Y_{\min}, Y_{\max}]$ to avoid false ground-plane collisions.
   - **Interactive Drag Rotation (Handle Knob & 2-Finger Twist)**:
     - Replaces discrete button presses with fluid touch dragging:
       1. **Rotation Handle Knob**: When an item is selected, a circular rotation handle knob and stem appear on the floor in front of the piece. Dragging the knob circularly spins the piece around its vertical Y-axis in real time.
       2. **Two-Finger Twist**: Users can twist two fingers anywhere in the viewport to rotate the selected piece.
     - **Magnetic Angle Snapping & Haptics**: Snaps magnetically to orthogonal 90° (and 45°) increments when within a $6.9^\circ$ ($0.12$ rad) threshold, triggering sensory haptic ticks (`.impact(weight: .light)`).
     - **Real-Time Collision Feedback**: Rotating into an obstacle instantly tints the halo and knob **RED**, blocks saving, and shows the overlap warning until resolved.

4. **Interior Drywall Bounding & Dual Architectural Lighting**:
   - **Interior Drywall Bounding**: Resolves LP-011 by dynamically inspecting the inner faces of `Arch_grp` wall prisms instead of the root visual bounds, preventing furniture from penetrating the ~0.50m wall thickness or protruding through exterior walls.
   - **Dual Architectural Lighting**: Installs a warm architectural key light (2200 lumens at $[2, 5, 3]$) and a soft ambient fill light (1400 lumens at $[-3, 4, -3]$), providing bright, professional dollhouse illumination without pitch-black shadows.
   - **Isometric Dollhouse Framing**: Camera pitch is restricted to a comfortable $[17^\circ, 54^\circ]$ range ($0.30 - 0.95$ rad) with a default elevation of $35^\circ$ ($0.62$ rad) centered on the room interior.

5. **Hardcoded Dashboard Featured Reference & SwiftData Seeding**:
   - `DashboardView` features a hard-coded **"Room-2 • 3D Studio"** card at the top of the dashboard for immediate 1-tap access to the colored reference environment and interactive rearrangement sandbox.
   - On appearance, `DashboardViewModel.ensureRoom2Seeded(context:)` idempotently seeds a "Room-2" `Room` with an "Original Layout" containing 5 grounded furniture pieces (`Queen Bed`, `Work Desk`, `Desk Chair`, `Sofa`, `Wardrobe`) pointing to `Room-2.usdz`.
   - Architectural PBR materials are dynamically applied: warm oak flooring on `Floor_grp` and matte white plaster on `Arch_grp`.

5. **SwiftData Persistence Boundary**:
   - Only collision-free coordinates and orientations are persisted to SwiftData. Invalid intersecting states remain transient in the viewport until resolved or reverted.

## Consequences

- Scanned rooms and custom layouts display their authentic geometry and furniture inventory.
- Mock room assets are isolated to headless testing and initial template seeds.
- Furniture manipulation respects physical architectural clearances without frustrating users trying to place desk chairs.

## Validation

- Unit tests in `ResignTests` verify:
  1. Room perimeter boundary clamping for arbitrary dimensions and orientations.
  2. Rigid furniture bounding box collision detection and rejection.
  3. Chair-to-desk tuck-in allowance permitting up to 65% overlap while preventing pass-through.
  4. 90° rotation snapping and coordinate bounding updates.
  5. Error state transitions when room USDZ is missing without mock room fallback.
