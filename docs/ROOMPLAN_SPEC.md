# RoomPlan LiDAR Capture & Sanitizer Specification

> Pure domain contract, pipeline architecture, and data transformation specifications for **Resign**'s RoomPlan capture pipeline.

---

## 1. Pipeline Overview

```text
[Hardware Gate: isSupported]
            │
            ▼
[RoomCaptureView (LiDAR Metal Shader)] ◄───► [Custom SwiftUI HUD Overlay]
            │
            ▼ (Emits CapturedRoom)
[CapturedRoomPayload (Decoupled Pure Swift Representation)]
            │
            ▼
[RoomCaptureSanitizer]
  - Floor Grounding Invariant for Seating (posY = 0.0)
  - Chair Deduplication (Backrest + Seat Cushion Proximity Merging)
  - Airborne Wall Artifact Filtering (Discards floating chairs >0.50m above floor)
  - Table & Desk Open Clearance Geometry (Tabletop slab + 4 corner legs)
  - Wall Alignment Snapping (±5° within 15 cm)
  - Residential Object Categorization (Bed, Sofa, Table, Chair, Storage, TV)
  - 1-Master Uniform Scaling by Width
            │
            ▼
[SwiftData Model Assembly]
  - Room (Dimensions, Coordinates, Timestamps)
  - RoomOpening (Windows, Doors)
  - Layout ("Original Scan", Furnitures)
            │
            ▼
[USDZ Export -> Documents/Rooms/<id>/scan.usdz]
            │
            ▼
[Navigation: AppRoute.orientation(roomId: UUID)]
```

---

## 2. Decoupled Pure Domain Contracts

To ensure sub-second unit testability without physical LiDAR hardware in CI/test suites, the mapper operates on a decoupled pure Swift payload protocol rather than private Apple framework types:

```swift
public struct ScannedWallPayload: Sendable, Equatable {
    public let id: UUID
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float> // length X, height Y, thickness Z
    public let rotationYaw: Float
    public let transform: simd_float4x4

    public var startPoint: SIMD2<Float> { ... }
    public var endPoint: SIMD2<Float> { ... }
}

public struct ScannedOpeningPayload: Sendable {
    public let type: String          // "window", "door", "opening"
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float> // width X, height Y, length Z
}

public struct ScannedObjectPayload: Sendable {
    public let rawCategory: String
    public let position: SIMD3<Float>
    public let dimensions: SIMD3<Float>
    public let rotationYaw: Float
}

public struct CapturedRoomPayload: Sendable {
    public let roomLength: Float     // Bounding Extent along Z
    public let roomWidth: Float      // Bounding Extent along X
    public let roomHeight: Float     // Bounding Extent along Y
    public let walls: [ScannedWallPayload]
    public let openings: [ScannedOpeningPayload]
    public let objects: [ScannedObjectPayload]
}
```

---

## 3. "Never Wrong" Sanitizer & Whitelist Rules

1. **Homeowner Living Category Whitelist**:
   Only objects matching residential living, sleeping, and study zones are accepted:
   - **Accepted & Categorized**:
     - `.bed` $\rightarrow$ `"bed"` (Master reference size: $1.60\text{ m} \times 2.00\text{ m}$)
     - `.sofa` $\rightarrow$ `"sofa"` (Master reference size: $2.10\text{ m} \times 0.95\text{ m}$)
     - `.table` $\rightarrow$ `"desk"` (if height $\approx 0.70\text{ m} - 0.78\text{ m}$ and aspect ratio suggests workstation) or `"table"` (dining/coffee table)
     - `.chair` $\rightarrow$ `"chair"` (Master reference size: $0.65\text{ m} \times 0.65\text{ m}$)
     - `.storage` $\rightarrow$ `"closet"` (Master reference size: $1.20\text{ m} \times 0.60\text{ m}$)
     - `.television` $\rightarrow$ `"television"` (Master reference size: $1.30\text{ m} \times 0.40\text{ m}$)
     - `.fireplace` $\rightarrow$ `"fireplace"` (Fixed obstacle; immovably grounded)

2. **Strict Bathroom & Appliance Discard (Zero False Porcelain)**:
   Any detections matching fixed plumbing or heavy appliances are automatically discarded to eliminate embarrassing misdetections (e.g., storage benches misclassified as bathtubs, ceramic stools as toilets):
   - **Silently Discarded**: `.bathtub`, `.toilet`, `.sink`, `.washerDryer`, `.dishwasher`, `.stove`, `.oven`, `.refrigerator`.

3. **Floor Grounding ($Y = 0.0$)**:
   All detected furniture objects are strictly grounded:
   $$\text{positionY} = 0.0$$
   Eliminating LiDAR vertical drift and floating objects.

4. **Proportional Uniform Scaling by Width**:
   $$\text{scale} = \frac{\text{detectedWidth}}{\text{masterAssetWidth}}$$
   Guarantees zero texture squishing or oval component deformation.

5. **Per-Segment Wall Alignment Snapping**:
   Rather than assuming 4 outer orthogonal planes, the sanitizer calculates the point-to-segment distance to each individual wall segment in the XZ plane. If an object is within $15\text{ cm}$ of a wall surface and oriented within $\pm 15^\circ$ of parallel/perpendicular, it snaps flush against the wall surface and locks yaw alignment.

---

## 4. Multi-Wall & Arbitrary Polygon USDZ Generation

Resign generates an authentic architectural USDZ model supporting both standard rectangular rooms and arbitrary polygonal geometry (L-shapes, hexagons, alcoves):
1. **Multi-Wall Segment Prisms**: Generates a distinct 3D box prism for each detected wall segment (`ScannedWallPayload`) using its real-world length, height, orientation, and $0.10\text{ m}$ thickness.
2. **Ear-Clipping Polygon Triangulation (`PolygonTriangulator`)**:
   - Reconstructs the 2D perimeter boundary polygon by chaining wall endpoints.
   - Deterministically triangulates arbitrary simple polygons (concave L-shapes, hexagons, n-gons) into indexed triangles with sub-millisecond execution.
   - Generates matching triangulated Floor and invisible Ceiling meshes.
3. **Dollhouse Ceiling Ergonomics**: Ceiling geometry is tagged with `visibility = "invisible"` allowing free top-down and isometric inspection while preserving ceiling height metadata.
4. **PBR Materials (`UsdPreviewSurface`)**:
   - **Walls**: Matte warm plaster (`diffuseColor = (0.92, 0.91, 0.88)`, `roughness = 0.85`).
   - **Floor**: Natural light oak planks (`diffuseColor = (0.76, 0.60, 0.42)`, `roughness = 0.45`).
   - **Windows**: Architectural glass (`opacity = 0.2`, `ior = 1.52`, bronze frame).
   - **Doors**: Solid warm wood panel with metallic hardware.

---

## 4. UI Architecture (`Resign/Features/RoomScan/`)

* **`RoomCaptureViewWrapper`**: `UIViewRepresentable` bridging Apple's `RoomCaptureView`.
* **`RoomScanOverlayView`**: Custom SwiftUI layer presenting:
  - Top bar with back/cancel control.
  - Live milestone indicators:
    - `Walls`: Checked once room boundary closed.
    - `Windows`: Shows detected aperture count for solar ephemeris readiness.
    - `Ceiling`: Confirms height lock for 5×5 lighting grid.
  - Primary bottom button: `[ Complete Scan & Orient Room ]`.
* **`RoomScanViewModel`**: State machine managing:
  - `.checkingHardware` $\rightarrow$ `.unsupported` (Non-LiDAR alert)
  - `.ready` $\rightarrow$ `.scanning` $\rightarrow$ `.processing` $\rightarrow$ `.completed(roomId: UUID)`
