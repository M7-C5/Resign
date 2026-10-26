# End-to-End View Navigation Architecture

* Status: accepted
* Date: 2026-10-26
* Deciders: Core Architecture Team, Antigravity Agent

## Context and Problem Statement

The application contains several implemented feature modules (`DashboardView`, `LayoutDetailsView`, `RoomScanView`, `RoomScanResultView`, `LightingSetupView`, and `Studio3DView`), but until now they operated as isolated screens or mockups. A unified, end-to-end navigation architecture is required to guide users seamlessly from initial LiDAR room capture through 3D review, ceiling light configuration, and persistent multi-layout exploration.

Placeholder screens (`OrientationView`, `InsightsView`, and `ARWalkthroughView`) are currently unimplemented and must not leave dead-ends in user journeys.

## Decision Drivers

* **Workflow Separation**: Clear boundary between active room creation (modal onboarding workflow) and steady-state room/layout browsing (hierarchical dashboard stack).
* **Navigation Continuity**: Fluid transitions between `RoomScanView` → `RoomScanResultView` → `LightingSetupView` with early-exit and rescan capabilities.
* **Direct Access & Editing**: Ability to inspect layouts in `Studio3DView` and adjust ceiling fixtures via `LightingSetupView` directly from saved room detail views.
* **SwiftData Safety**: Using type-safe identifiers (`UUID`) for navigation route parameters to avoid holding stale persistent model references across route changes.
* **Unimplemented Screen Isolation**: Restrict user journeys strictly to fully implemented views, avoiding stub/placeholder dead-ends.

## Considered Options

* **Option 1: Flat NavigationStack in Dashboard**: Push every screen (including LiDAR scanning and result review) directly onto the root `DashboardView` navigation stack.
* **Option 2: Dedicated FullScreenCover Flow for Creation + Push Navigation for Details**: Host the room creation pipeline (`RoomScanView` → `RoomScanResultView` → `LightingSetupView`) inside an isolated `fullScreenCover` with its own `NavigationStack`, while `LayoutDetailsView`, `Studio3DView`, and detail lighting editing push onto the main `DashboardView` navigation stack.

## Decision Outcome

Chosen option: **Option 2: Dedicated FullScreenCover Flow for Creation + Push Navigation for Details**, because it creates a focused, modal mental model for physical room capture without corrupting the dashboard's navigation history, while allowing instant dismissal back to the populated dashboard upon completion.

### Architecture Specifications

1. **Room Creation Coordinator (`RoomCreationFlowView`)**:
   - Hosted via `.fullScreenCover(isPresented: $isShowingRoomCreation)` from `DashboardView`.
   - Manages an isolated `NavigationStack(path: $path)` parameterized by `RoomCreationRoute`:
     - `.result(roomId: UUID)`: Displays `RoomScanResultView`.
     - `.lightingSetup(layoutID: UUID)`: Displays `LightingSetupContainerView` wrapping `LightingSetupView`.
   - Early completion ("Save & Finish" or "Save & Continue") or cancellation cleanly dismisses the entire cover, returning to the Dashboard.
2. **Result View Actions (`RoomScanResultView`)**:
   - Primary action: "Continue to Lighting Setup" pushes `.lightingSetup(layoutID:)`.
   - Secondary actions: "Save & Finish" dismisses the creation flow; "Scan Again" pops back to scanner root.
3. **Saved Layout Exploration (`LayoutDetailsView`)**:
   - "Open in 3D" pushes `Studio3DView()`.
   - "Configure Ceiling Lights" pushes `LightingSetupView(layout:)`.
4. **Quick Simulation Access**:
   - Toolbar button (`sun.max`) in `DashboardView` pushes `Studio3DView()`.

### Positive Consequences

* Physical scanning and light configuration form an uninterrupted, cohesive pipeline.
* Saved layouts can be revisited, explored in 3D, and their lights re-configured at any time.
* Clean back navigation and cancellation semantics prevent orphaned or corrupt state.
* Only fully implemented production views are reachable by the user.

### Negative Consequences

* Modal transition requires passing dismiss callbacks and coordinating SwiftData saves before dismissal.
