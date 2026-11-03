# Architecture Blueprint — Resign

> Technical specification, domain schema, spatial algorithms, and architectural decisions for **Resign** (3D Room Rearranger & Sunlight Simulator).

---

## 1. Executive Summary & Design Decisions

Through the comprehensive `/grill-me` architectural design review, all foundational technology and user experience branches have been established:

| Domain | Decision | Architectural Rationale |
| :--- | :--- | :--- |
| **3D & Spatial Engine** | **RealityKit (`RealityView`)** | Modern Apple spatial standard (iOS 17+), native USDZ rendering, physically based shadows, seamless ARKit anchoring. |
| **Room Capture Pipeline** | **Apple RoomPlan Framework** | First-party LiDAR room scanning (`RoomCaptureSession`) extracting architectural walls, openings, and bounding boxes. |
| **Geometry Inspection** | **ModelIO Framework** | Headless mesh inspection (`MDLAsset`, `MDLMesh`) for calculating precise object bounding boxes and transforms. |
| **Tactile Ergonomics** | **CoreHaptics Framework** | Tactile feedback for wall snapping, collision avoidance, and 90cm corridor boundary warnings. |
| **State Management** | **Observation Framework (`@Observable`)**| iOS 17+ fine-grained view reactivity eliminating redundant re-renders during 60fps 3D gesture manipulation. |
| **Hardware Strategy** | **Strict LiDAR Requirement** | RoomPlan LiDAR is strictly required. Non-LiDAR devices are greeted with a dedicated hardware requirement screen. |
| **Asset Pipeline** | **Bundled Curated USDZ Catalog** | App bundle contains stylized, optimized USDZ models (bed, desk, sofa, etc.) scaled non-uniformly to match RoomPlan bounding boxes. |
| **Natural Sunlight Engine**| **NOAA Solar Ephemeris Algorithm**| Real-world astronomical sun vector calculations (azimuth & elevation) using device latitude, longitude, and 24-hour time of day. |
| **Artificial Light Mapping**| **2D Interactive Ceiling Grid (5×5)**| Touch-enabled top-down grid overlay on the room floorplan for dropping fixtures with Lumens (0–2000 lm) and Kelvin (2200K–6500K) controls. |
| **Layout Generator** | **Deterministic Swift Rules + LLM** | Mathematical clearance corridors (>= 90cm), window glare vectors, and Feng Shui command positions generate 3 layouts; LLM provides natural language design rationales. |
| **3D Object Interaction** | **Sims-Style Radial Menu + Floor Drag**| Tapping furniture spawns floating action pills (Rotate, Slide, Archive); dragging is strictly constrained to the floor plane ($Y=0$) with boundary collision snapping. |
| **Augmented Reality Mode** | **1:1 Full-Scale Physical Immersion** | Virtual furniture is superimposed directly onto the user's actual room at true 1:1 scale for real-world physical walkthroughs. |
| **Data Persistence** | **Hierarchical SwiftData Schema** | `Room` (with `RoomOpening`) owns multiple `Layout` revisions containing `Furniture`, `Light`, and `Insight` records. |

---

## 2. System Architecture Diagram

```
+-----------------------------------------------------------------------------------+
|                                 SwiftUI UI LAYER                                   |
|   - RoomListView (Dashboard)           - RoomPlanScanView (LiDAR Capture)         |
|   - CompassAlignmentView (True North)   - CeilingLightGridView (5x5 Light Mapper)  |
|   - InsightReportView (Diagnostics)     - RoomStudioView (Interactive 3D RealityKit)|
|   - ARWalkthroughView (1:1 Immersion)   - LayoutComparisonView (Original vs Recs) |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
|                            DOMAIN ENGINES (Pure Swift)                            |
|                                                                                   |
|  [NOAA Solar Ephemeris Engine]          [Spatial Heuristic Optimizer Engine]       |
|  - Inputs: Lat, Lon, Date, Time, Heading - Circulation Corridors (>= 90cm)        |
|  - Outputs: Azimuth & Elevation Angles  - Window Glare Vector Analysis             |
|  - DirectionalLightEntity Vector         - Feng Shui Command Position Scoring      |
|                                          - Generates 3 Mathematically Distinct Recs|
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
|                        REALITYKIT & ASSET SUBSYSTEM                               |
|  - RoomPlan USDZ Importer               - Bounding Box Asset Scaler               |
|  - RealityView Gesture Recognizers      - Floor Plane Drag Constraint (Y=0)       |
|  - Directional Sun Entity + PointLights - Orthographic Camera Snapping (5 Views)  |
|  - ARKit 1:1 World Tracking Session     - Furniture Inventory Archive Bin         |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
|                           SWIFTDATA PERSISTENCE LAYER                             |
|  - Room (Name, Longitude, Latitude, Compass, Dimensions, Openings, Layouts)       |
|  - RoomOpening (Type, Position X/Y/Z, Dimensions)                                 |
|  - Layout (Name, USDZ URL, Furnitures, Lights, Insights, Timestamps)              |
|  - Furniture (Name, Category, Texture, Position X/Y/Z, Yaw, Dimensions, Archived) |
|  - Light (Name, Coordinate X/Y, Elevation Z, Brightness, ColorTemp, IsOn)         |
|  - Insight (Title, Type, Detail)                                                  |
+-----------------------------------------------------------------------------------+
```

---

## 3. Data Schema & Models

```mermaid
erDiagram
    Room ||--o{ RoomOpening : has
    Room ||--o{ Layout : contains
    Layout ||--o{ Furniture : arranges
    Layout ||--o{ Light : includes
    Layout ||--o{ Insight : reports

    Room {
        UUID id PK
        String name
        Double longitude
        Double latitude
        Double compass
        Float length
        Float width
        Float height
        Date createdAt
        Date updatedAt
    }

    RoomOpening {
        UUID id PK
        String type
        Float posX
        Float posY
        Float posZ
        Float width
        Float height
    }

    Layout {
        UUID id PK
        String name
        URL usdzURL
        Date createdAt
        Date updatedAt
    }

    Furniture {
        UUID id PK
        String name
        String category
        String texture
        Float positionX
        Float positionY
        Float positionZ
        Float rotationYaw
        Float length
        Float width
        Float height
        Boolean isArchived
        URL usdzURL
    }

    Light {
        UUID id PK
        String name
        Float coordinateX
        Float coordinateY
        Float elevationZ
        Float brightness
        Int colorTemp
        Boolean isOn
    }

    Insight {
        UUID id PK
        String title
        String type
        String detail
    }
```

---

## 4. Key Spatial & Physical Algorithms

### A. NOAA Astronomical Solar Ephemeris Engine
Calculates the exact sun vector in room coordinate space:
1. **Julian Day Calculation**: Converts the specified local time and date to Universal Time (UTC) and computes the fractional Julian day.
2. **Solar Declination & Equation of Time**: Solves for the sun's celestial position relative to Earth's axial tilt.
3. **Local Solar Time**: Adjusts clock time by longitude offset ($4 \text{ min/degree}$) and the equation of time.
4. **Solar Zenith & Azimuth**:
   $$\cos(\theta_z) = \sin(\phi)\sin(\delta) + \cos(\phi)\cos(\delta)\cos(h)$$
   where $\phi$ is latitude, $\delta$ is solar declination, and $h$ is hour angle.
5. **Room Coordinate Transform**: Rotates the real-world solar azimuth by the room's true-north alignment heading:
   $$\theta_{\text{room}} = \theta_{\text{solar}} - \theta_{\text{true\_north}} - \theta_{\text{avatar\_offset}}$$
6. **RealityKit DirectionalLightEntity**: Directly updates the sunlight direction and color temperature (Kelvin to RGB gradient) to cast physically accurate window shadows in real time.

### B. Spatial Clearance & Layout Scoring Engine
Evaluates layouts across 3 objective mathematical dimensions:
1. **Circulation Clearance Score ($S_{\text{circ}}$)**:
   - Constructs a 2D navigation grid of the room floor.
   - Calculates path width between doors, windows, and furniture edges.
   - Penalizes any primary walking corridor narrower than **90 cm (36 inches)**.
2. **Daylight & Glare Optimization Score ($S_{\text{light}}$)**:
   - Desks: Rewards placement where natural light arrives from the side ($70^\circ - 110^\circ$ to monitor screen vector) while penalizing direct window backlighting (glare).
   - Seating/Reading: Rewards positioning within the direct solar illumination polygon during daylight hours.
3. **Command Position & Ergonomics Score ($S_{\text{ergo}}$)**:
   - Beds/Desks: Rewards placement where the occupant can see the primary door without being directly in line with the doorway (Feng Shui / psychological comfort).
   - Headboards: Must anchor firmly against solid walls rather than floating in open circulation paths or blocking windows.

### C. The 3 Generated Recommendations:
- **Layout 1: Circadian Productivity**: Maximizes natural sunlight on active work/study zones (desks, reading nooks) with zero screen glare.
- **Layout 2: Open Flow & Circulation**: Maximizes central continuous floor space and ensures all entry/exit corridors exceed 100 cm.
- **Layout 3: Restful Sanctuary**: Places beds and relaxation zones in maximum shadow zones shielded from direct door sightlines and outside window drafts.

### D. Panero & Zelnik Clearance Engine & AI Diagnostic Pipeline (ADR 0037)
Connects scanned room data to deterministic clearance checks and LLM qualitative reasoning:
1. **Rulebook Thresholds (Panero & Zelnik Standard)**:
   - **R1 (Walkways Critical)**: $\ge 76.2\text{ cm}$ (30 inches).
   - **R2 (Walkways Recommended)**: $\ge 91.4\text{ cm}$ (36 inches).
   - **R3 (Desk Rear Clearance)**: $\ge 76.2\text{ cm}$ for task chair pullback and egress.
   - **R4 (Bed Operational Zone)**: $66 - 99\text{ cm}$ for making beds and perimeter circulation.
   - **R5 (Under-Bed Storage)**: $116 - 157\text{ cm}$ for drawer and under-bed pullout access.
   - **R6 (Door Swing Arc)**: $100\%$ unobstructed ($0\text{ cm}$ margin allowed).
2. **Compact Centimeter Representation**:
   - Room bounding boxes and openings are converted to rounded centimeters and pure semantic roles (`bed`, `desk`, `chair`, `wardrobe`, `sofa`, `tv`).
   - The LLM prompt explicitly forbids generating 3D coordinates or collision geometry.
3. **Hallucination Gatekeeper**:
   - `AIDiagnosticValidator` filters every returned furniture UUID against active scene items, guaranteeing 3D RealityKit stability.
4. **Solver Settings & 3D Highlight Rings**:
   - Solver settings (pinned items, must-haves, goal weights) drive `LayoutOptimizerEngine`.
   - Clashing furniture UUIDs are emitted to `Studio3DViewModel.highlightedFurnitureIDs` to project visual highlight rings around conflicting items.

---

## 5. Codebase Layout & Architectural Invariants

The repository is organized following the **Vertical Feature-Slice Architecture** to maximize team velocity, prevent git merge collisions, and guarantee 120 FPS rendering performance:

```text
Resign/
├── App/                                // App lifecycle & Navigation router
│   ├── ResignApp.swift
│   └── Navigation/
│       └── AppRoute.swift             // Type-safe enum AppRoute: Hashable
├── Features/                          // Vertical Feature Slices (V + VM)
│   ├── Dashboard/                     // DashboardView, DashboardViewModel
│   ├── RoomScan/                      // RoomScanView, RoomScanViewModel
│   ├── LightingSetup/                 // LightingSetupView, LightingSetupViewModel
│   ├── Insights/                      // SpatialJourneyFlowView, PreferencePageView, YourLayoutResultView, LayoutSuggestionsDisplayView, InsightsView, InsightsViewModel
│   ├── Studio3D/                      // Studio3DView, Studio3DViewModel, Studio3DSuggestionView
│   │   └── Lighting/                  // RoomSimulationView, RoomLightingRig, scene controller
│   └── ARWalkthrough/                 // ARWalkthroughView, ARWalkthroughViewModel
├── Core/                              // Horizontal Foundation (The "Brain", Zero UI)
│   ├── Models/                        // SwiftData @Model skeleton classes
│   │   ├── Room.swift
│   │   ├── RoomOpening.swift
│   │   ├── Layout.swift
│   │   ├── Furniture.swift
│   │   ├── Light.swift
│   │   └── Insight.swift
│   ├── Algorithms/                    // Pure math engines
│   │   ├── SolarEphemerisEngine.swift
│   │   ├── SpatialClearanceEngine.swift
│   │   └── LayoutOptimizerEngine.swift
│   └── Spatial/                       // Shared 3D RealityKit helpers
│       ├── ProceduralRoomUSDZGenerator.swift
│       ├── RoomCaptureMapper.swift
│       ├── RoomCapturePayload.swift
│       ├── RoomCaptureSanitizer.swift
│       ├── FurnitureEntityFactory.swift
│       └── SunlightEntityController.swift
└── Services/                          // Hardware & System Providers
    ├── LocationService.swift
    ├── RoomRepository.swift
    └── ModelContainer+Testing.swift
```

### Key Architectural Invariants:
1. **The Inward Dependency Rule**: `Core/` has zero dependencies on `Features/`. It can compile and be tested headlessly in milliseconds.
2. **Inter-Feature Isolation ("No Peer Imports")**: Features never directly instantiate or reference peer feature view models. All navigation and cross-feature routing is coordinated via `AppRoute` passing IDs (never live `@Model` object references).
3. **Skeleton State**: All classes and structs currently exist as clean, unopinionated skeletons with empty initializers (`init() {}`), ready for collaborative, contract-first implementation.

