# ADR 0007: RoomPlan LiDAR Capture and Geometric Sanitizer Pipeline

* Status: accepted
* Date: 2026-10-20
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign relies on Apple's RoomPlan framework for real-world room capture on iPhone Pro devices. However, raw RoomPlan scans present distinct technical challenges:
1. **Visual Presentation**: Apple's stock `RoomCaptureView` has generic system buttons and lacks Resign-specific scanning coaching (such as confirming windows for sunlight and ceilings for light grids).
2. **LiDAR Measurement Noise**: Bounding boxes can float above the floor ($Y > 0$), slightly intersect walls, or carry continuous fractional measurement noise.
3. **Asset Distortion Risk**: Non-uniform scaling of 3D models distorts geometry and texture aspect ratios.
4. **Coordinate Frame**: RoomPlan's coordinate origin is camera-relative, requiring downstream True North compass and avatar orientation alignment before sunlight simulation can run.

We must define the scanning architecture, UI presentation model, sanitization algorithms, and domain translation contracts.

## Decision Drivers

* **"Never Wrong" Quality Bar**: Output geometry must be mathematically grounded on the floor ($Y = 0.0$) with clean wall alignment and zero floating boxes.
* **Proportional 3D Model Scaling**: 1 Master USDZ model per category scaled uniformly by width, avoiding distorted mesh components and keeping the app bundle lightweight.
* **Domain-Specific Guidance**: The scanner HUD must explicitly coach users to capture windows and ceilings required for subsequent solar and photometric simulation.
* **Sub-Second Testability**: Pure domain contracts must be decoupled from private Apple AR frameworks, enabling automated unit testing without physical LiDAR hardware.

## Considered Options

1. **Option 1: Stock Apple Turnkey UI**: Use `RoomCaptureView` with Apple's default buttons and zero custom overlay. Rejected because it lacks domain-specific milestone tracking (windows, ceiling) and branded aesthetics.
2. **Option 2: 100% Custom From-Scratch Scanner**: Build an ARKit camera session and write custom Metal shaders for live LiDAR wireframe rendering. Rejected due to extreme graphics complexity and duplication of Apple's private shaders.
3. **Option 3: Hybrid Overlay on `RoomCaptureView` with Decoupled Sanitizer**: Render Apple's 60 FPS real-time LiDAR line shader via `RoomCaptureView`, overlay Resign's custom SwiftUI HUD, and pipe `CapturedRoom` through a pure Swift `RoomCaptureSanitizer`.

## Decision Outcome

Chosen option: **Option 3: Hybrid Overlay on `RoomCaptureView` with Decoupled Sanitizer**.

### Architectural Contract

1. **UI Layer (`RoomScanView`)**:
   - `RoomCaptureViewWrapper` renders camera feed and Apple's LiDAR wireframe shader.
   - `RoomScanOverlayView` overlays Resign branding, live milestone chips (`Walls`, `Windows`, `Ceiling`), and custom completion buttons.
2. **Pure Domain Payload (`CapturedRoomPayload`)**:
   - Decoupled Swift data structures (`ScannedObjectPayload`, `ScannedOpeningPayload`) that mirror `CapturedRoom` data without requiring live camera hardware.
3. **Geometric Sanitizer (`RoomCaptureSanitizer`)**:
   - Enforces Homeowner Living Whitelist (`bed`, `sofa`, `chair`, `table`, `storage`, `television`, `fireplace`).
   - Automatically discards bathroom fixtures and heavy appliances (`bathtub`, `toilet`, `sink`, `washerDryer`, `dishwasher`, `stove`, `oven`, `refrigerator`) to prevent false porcelain misdetections.
   - Strictly enforces floor grounding: $\text{positionY} = 0.0$.
   - Applies wall alignment snapping for parallel items within $15\text{ cm}$.
   - Calculates uniform scaling factor: $\text{scale} = \text{detectedWidth} / \text{masterWidth}$.
4. **SwiftData Assembly**:
   - Assembles and persists `Room`, `RoomOpening`s, and initial `Layout` ("Original Scan").
   - Exports raw parametric USDZ to `Documents/Rooms/<id>/scan.usdz`.
   - Transitions to Step 4: `AppRoute.orientation(roomId: UUID)`.

### Consequences

* Clean separation between Apple hardware views and pure Swift mapping logic.
* High visual fidelity with zero texture stretching across all residential furniture.
* Fast, headless unit testing in `ResignTests` via synthetic payloads.
