# Resign Engineering Roadmap

> Phased implementation plan for the **Resign** 3D room rearranger and natural sunlight simulation app.

---

## 🎯 Phase Overview & Milestone Tracking

```
[Phase 1] Domain & Solar Physics (Core Swift Models + NOAA Ephemeris + Unit Tests)
   |
   v
[Phase 2] Spatial Optimization & Diagnostics (Circulation Math + Glare Vectors + 3 Layouts)
   |
   v
[Phase 3] RoomPlan LiDAR Capture & Compass Sync (LiDAR Gate + RoomCaptureSession + True North)
   |
   v
[Phase 4] Photometric Light Grid (2D 5x5 Ceiling Projection + Lumens & Kelvin Calibration)
   |
   v
[Phase 5] RealityKit 3D Studio (Sims-Style Radial Menu + Floor Plane Drag + 24h Sun Slider)
   |
   v
[Phase 6] 1:1 Immersive AR Walkthrough (ARKit World Tracking + Physical Room Superimposition)
```

---

## 📋 Detailed Phase Breakdown

### Phase 1: Core Domain Architecture & Solar Ephemeris Engine
- [ ] **Data Model Scaffolding**: Replace template `Item` with `ScannedRoom`, `RoomLayout`, `FurniturePlacement`, `LightSource`, and `RoomInsight` in SwiftData.
- [ ] **In-Memory Test Harness**: Extend `TestModelContainer` with factory presets and sample room fixtures.
- [ ] **NOAA Solar Ephemeris Algorithm**: Implement pure Swift astronomical calculation:
  - Julian day & solar declination calculation.
  - Hour angle, solar elevation, and solar azimuth math.
  - Room coordinate system rotation (accounting for true north heading and avatar offset).
- [ ] **Unit Tests**: 100% test coverage for solar angle predictions at known equinoxes, solstices, and global coordinates.

### Phase 2: Spatial Heuristic Optimization & Insight Engine
- [ ] **Circulation Grid & Corridor Analysis**: Compute 2D navigation mesh; detect walkway bottlenecks narrower than 90 cm.
- [ ] **Daylight & Glare Vector Scoring**: Calculate angle between desk/screen vectors and window daylight paths to prevent direct backlighting.
- [ ] **Command Position Rules**: Score bed and desk headboard placement against primary door sightlines.
- [ ] **3-Layout Generation Engine**:
  - *Layout 1: Circadian Productivity* (max natural light on work zones).
  - *Layout 2: Open Flow & Circulation* (max unobstructed central floor space).
  - *Layout 3: Restful Sanctuary* (sleep zones shielded from drafts and direct sightlines).
- [ ] **Diagnostic Insight Generator**: Produce actionable pros/cons cards based on spatial rule violations.

### Phase 3: Hardware Gating, RoomPlan LiDAR Capture & True North Compass
- [ ] **Hardware Compatibility Gate**: Check `RoomCaptureSession.isSupported`; render native alert/screen on non-LiDAR devices.
- [ ] **RoomPlan Capture Flow**: Embed `RoomCaptureView` with real-time room mesh scanning and object classification.
- [ ] **USDZ Generation & Asset Replacement**: Map RoomPlan bounding boxes to bundled curated 3D USDZ models.
- [ ] **CoreLocation & Compass Alignment**:
  - Live magnetometer compass interface.
  - 2-second steady north lock trigger.
  - Virtual avatar orientation sync to align virtual space with real physical view.

### Phase 4: Photometric Light Grid (5×5 Ceiling Overlay)
- [ ] **Interactive Ceiling Grid View**: 2D floorplan projection with 5×5 touchable grid cells.
- [ ] **Light Placement Gestures**: Tap-to-place light fixtures with coordinate assignment.
- [ ] **Photometric Control Sliders**: Real-time adjustments for Lumens (0–2000 lm) and Correlated Color Temperature (2200K Candle to 6500K Daylight).

### Phase 5: RealityKit Interactive 3D Studio
- [ ] **RealityView Studio Canvas**: Render room model with orbit, pan, and zoom camera controls.
- [ ] **Sims-Style Object Interaction**:
  - Tapping furniture spawns floating radial action pills (Rotate, Slide, Archive).
  - Floor plane dragging constrained strictly along $Y=0$ with wall boundary snapping.
  - Rotation in discrete 15° / 45° / 90° increments.
- [ ] **Sunlight & Time-of-Day Slider**: Real-time 24-hour scrubbing driving directional light entity with dynamic shadows cast through window openings.
- [ ] **Orthographic Camera Snapping**: 5 preset perspective buttons (Top-down, Left, Right, Front, Back).
- [ ] **Furniture Archive Bin**: Hide/store furniture items to simulate minimalist or decluttered arrangements.

### Phase 6: 1:1 Immersive Augmented Reality Walkthrough
- [ ] **ARKit World Tracking Session**: Anchor the modified virtual room at 1:1 real-world physical scale.
- [ ] **Physical Walkthrough Experience**: Let users physically walk through their room to evaluate clearances and furniture scale in place.
- [ ] **Lighting Reality Blend**: Blend virtual directional sunlight with real ambient environment lighting.
