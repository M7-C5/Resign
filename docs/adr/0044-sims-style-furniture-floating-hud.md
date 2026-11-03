# ADR 0044: Sims-Style Projected Furniture Floating HUD and Control Streamlining

## Context and Problem Statement
In the 3D Studio rearrangement workspace on iPad, users interact with furniture directly in a 3D RealityKit environment. Previously, selected furniture manipulation was split across two distinct surfaces:
1. **3D Floor Stem and Knob (`FurnitureRotationHandle`)**: A procedural 3D entity attached to the floor next to the furniture. On touch devices, this knob frequently collided with adjacent furniture footprints, was visually occluded at low camera pitch angles, and cluttered the floor plane.
2. **Fixed Bottom-Right Selection Card (`selectionActionCard`)**: A static SwiftUI card docked in the bottom-right corner showing furniture name, dimensions, archive button, and deselect trigger. On large iPad displays, this card was far removed from the user's focal point on the 3D entity, introducing cognitive friction and finger travel.

## Decision Drivers
- **Direct Manipulation Ergonomics**: Action controls (rotate, archive) must sit immediately adjacent to the manipulated entity in screen space, akin to classic architectural simulator ("The Sims") pie menus.
- **Clean Floor Plane**: Eliminate non-architectural procedural handles (torus/stem knobs) from the RealityKit scene graph.
- **Apple HIG & Touch Targets**: Floating action buttons must satisfy the minimum 44pt touch target requirement, provide rich haptic feedback, and support Dynamic Type.
- **Dual-Mode Rotation Ergonomics**: Architectural rearrangement benefits from fast 90° wall squaring on tap, while allowing continuous drag rotation for non-orthogonal rooms.

## Considered Options
1. **Retain Floor Handles and Bottom Card**: Continue with static bottom HUD and 3D rotation stem.
   - *Downside*: Excessive screen travel on iPad; occlusion and touch ambiguity in dense room layouts.
2. **RealityKit 3D Floating Billboards**: Render buttons as 3D `BillboardComponent` unlit meshes floating in the scene graph.
   - *Downside*: Poor text rendering, lacks native SwiftUI material vibrancy, complex touch event triage.
3. **Screen-Space Projected SwiftUI Floating HUD**: Project the selected 3D entity's top-center into 2D screen coordinates using `ARView.project(_:)` and overlay a responsive SwiftUI glassmorphic HUD directly above the piece.
   - *Upside*: Native SwiftUI ergonomics, liquid-smooth animations, 44pt HIG targets, and zero 3D scene clutter.

## Decision Outcome
Chosen Option: **Option 3 (Screen-Space Projected SwiftUI Floating HUD)**.

### Architectural Invariants & Flow

```
                      [ Selected 3D Furniture ]
                                 ▲
             (real-time projection via arView.project)
                                 │
                 ┌───────────────┴───────────────┐
                 │    [ ↻ Rotate ]   [ 📦 Archive ]   │  ← Circular Glassmorphic Buttons
                 │   "Work Desk · 1.4m × 0.7m"   │  ← Compact Metadata Pill
                 └───────────────────────────────┘
```

1. **Projection Pipeline**:
   - `RoomSimulationView` evaluates `arView.project(topCenter)` where `topCenter = [container.position.x, bounds.max.y + 0.08, container.position.z]`.
   - Anchoring to the entity's stable position anchor prevents the HUD from wobbling as non-square bounding boxes rotate.
   - The projected `CGPoint` updates on selection, camera orbit, furniture floor translation, and scene render events.
2. **Sims-Style Actions & Circular Halo Dial**:
   - **Circular Halo Dial**: A translucent circular disc (`Color.white.opacity(0.48)`) centered directly over the furniture centroid, with hit-testing disabled so 3D furniture underneath remains directly selectable and draggable for floor translation.
   - **Rotate Button**: Docked on the perimeter of the circular halo. Tapping triggers `Studio3DViewModel.rotateSelectedFurniture45(in:context:)` with snappy haptic feedback, stepping clockwise in 45° increments. Dragging tracks **2D circular angular motion around the furniture centroid**:
     $$\Delta\theta = \text{atan2}(v_{\text{prev}}.x \cdot v_{\text{curr}}.y - v_{\text{prev}}.y \cdot v_{\text{curr}}.x, \; v_{\text{prev}}.x \cdot v_{\text{curr}}.x + v_{\text{prev}}.y \cdot v_{\text{curr}}.y)$$
     This pure trigonometric formulation ensures uniform clockwise rotation ($\Delta\theta > 0$) and counter-clockwise rotation ($\Delta\theta < 0$) across all four quadrants without any quadrant flip or 90°/180° singularity. While dragging, the Rotate button glides along the dial rim under the user's finger and springs back smoothly upon release.
   - **Archive Button**: Docked on the perimeter of the halo (at top-left). Tapping triggers `Studio3DViewModel.archiveFurniture(id:in:context:)` with spring collapse into the inventory drawer.
3. **Selection-Gated Movement**:
   - Users must explicitly tap/press a furniture item to select it before it can be moved across the floor.
   - Panning on an unselected item orbits the camera, preventing accidental furniture displacement during room navigation.
4. **Streamlined UI Hierarchy**:
   - The static bottom-right `selectionActionCard` is removed.
   - `FurnitureRotationHandle` in `FurnitureEntityFactory` is retired.
5. **Deselection Protocol**:
   - Tapping empty floor/background deselects the item and dismisses the floating HUD.
   - Tapping another furniture item transfers selection immediately.
6. **Navigation Header Unification**:
   - Point of View presets (`rotate.3d`), AR placeholder, and Lighting simulation controls are aligned on the exact horizontal baseline as the back button (`chevron.left`).
   - Styled with Apple New York serif typography (`StudioTheme.titleFont`) and a warm architectural palette (`StudioTheme.canvasBackground`, `#F8F2E8` canvas, and `StudioTheme.primaryText`, `#6D4531` walnut).

## Consequences

### Positive
- Intuitive, game-like spatial manipulation on iPad with minimal finger travel.
- Clutter-free floor plane in RealityKit scenes.
- Snappy 90° rotation on tap with fluid free-rotation on drag.

### Negative / Trade-Offs
- Entities framed extremely close to the top screen edge require vertical clamping (`max(60, screenY - offset)`) to avoid status bar overlap.
