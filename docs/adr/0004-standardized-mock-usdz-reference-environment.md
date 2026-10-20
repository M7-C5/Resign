# ADR 0004: Standardized Mock USDZ Reference Environment for Simulation Testing

* Status: accepted
* Date: 2026-10-20
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign's domain algorithms (circadian sunlight simulation, photometric fixture calculations, spatial clearance heuristic scoring, and layout optimization) require continuous testing and rapid feedback. Relying exclusively on physical RoomPlan LiDAR room captures introduces major engineering bottlenecks:
1. Physical device and room dependencies during early development.
2. Unpredictable room geometries, wall orientations, and window dimensions across developer machines.
3. Lack of a known ground-truth benchmark for deterministic raycasting and sun-shadow angle verification.

We need a standardized, reproducible, bundled 3D USDZ reference room that models a standard furnished bedroom/studio with defined openings and furnishings.

## Decision Drivers

* **Ground-Truth Determinism**: Fixed spatial dimensions ($5.0\text{ m} \times 4.2\text{ m} \times 2.6\text{ m}$) enabling exact mathematical verification of solar vectors and shadow projections.
* **Photorealistic & Architectural Fidelity**: Sharp planar geometry with PBR materials (`UsdPreviewSurface`) that render consistently across RealityKit, SceneKit, and QuickLook.
* **Zero Runtime Overhead**: Bundled directly into the app bundle without network or external tool dependencies.
* **Dollhouse Inspection Ergonomics**: The 3D viewport must allow intuitive top-down and isometric inspection without an opaque ceiling blocking interior visibility.

## Considered Options

1. **Option 1: Require Physical RoomPlan Scans Only**: Force developers and testers to scan real rooms before testing algorithms.
2. **Option 2: Import Generic Third-Party CAD / OBJ Assets**: Download free online models and convert them to USDZ.
3. **Option 3: Procedural In-Repo USD Generator Script**: Author an in-house Python generator script using standard OpenUSD syntax with explicit metric dimensions, materials, and hierarchy.

## Decision Outcome

Chosen option: **Option 3: Procedural In-Repo USD Generator Script**, because:
1. **Full Parameter Control**: Exact millimeter control over window sill height, wall cutouts, and furniture bounding boxes.
2. **Apple RealityKit Alignment**: Uses standard USD prim hierarchy (`/Room/Structure`, `/Room/Openings`, `/Room/Furniture`), allowing direct entity querying via `Entity.findEntity(named:)`.
3. **Subdivision Hardening**: Explicitly enforces `uniform token subdivisionScheme = "none"`, avoiding OpenUSD's default Catmull-Clark rounding trap that degrades boxes into marshmallow ellipsoids.
4. **Camera Ergonomics**: Configures ceiling geometry as `uniform token visibility = "invisible"`, enabling seamless top-down dollhouse viewing while retaining full geometry for raycast occlusion testing.

### Key Architectural Specifications
* **Metric Frame**: Right-handed Y-up (`metersPerUnit = 1.0`, `upAxis = "Y"`).
* **Room Enclosure**: $5.0\text{ m}$ (W) $\times 4.2\text{ m}$ (D) $\times 2.6\text{ m}$ (H) with $0.10\text{ m}$ perimeter walls.
* **Sunlight Vector Opening**: East-facing window ($1.6\text{ m} \times 1.2\text{ m}$ with architectural glass) optimized for morning circadian sun sweeps ($070^\circ$–$110^\circ$ azimuth).
* **Ingress Opening**: South-facing door ($0.9\text{ m} \times 2.1\text{ m}$) establishing a $>1.0\text{ m}$ circulation corridor.
* **Furnishings (6 Items)**: Queen Bed, Desk, Task Chair, 3-Seater Sofa, Wardrobe Closet, and 55-inch OLED TV with Walnut Console.

### Positive Consequences

* Engineers working on the Solar Ephemeris and Lighting Simulation engines have an immediate, reproducible 3D test stage.
* Unit tests in `ResignTests` can load and query the reference room in sub-second test passes.
* Eliminates simulator rendering glitches caused by default Catmull-Clark subdivision surfaces.

### Negative Consequences

* Synthetic geometry uses bounding boxes with PBR textures rather than complex high-poly sculpted meshes (which will be substituted by the asset catalog in later phases).
