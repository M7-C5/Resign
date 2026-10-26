# Dashboard Persistence and Navigation Architecture

* Status: accepted
* Date: 2026-10-26
* Deciders: Core Architecture Team, Antigravity Agent

## Context and Problem Statement

Initial UI work in the dashboard introduced prototype screens (`DashboardView`, `LayoutCardView`, and `LayoutDetailsView`) backed by transient `@State private var layouts: [String]`. This disconnected the UI from the app's established SwiftData models (`Room`, `Layout`), omitted navigation to `Studio3DView`, left the `+` room creation action unhandled, and hardcoded light mode colors. 

We need a clean architectural contract connecting the dashboard UI to SwiftData persistence, restoring end-to-end navigation between room scanning, layout management, and 3D lighting simulation, and organizing subviews into a maintainable component structure.

## Decision Drivers

* **Domain Integrity**: Align with the authentic whiteboard domain schema defined in ADR 0005 and ADR 0006 (`Room` $\rightarrow$ `Layout` $\rightarrow$ `Furniture` / `Light`).
* **Navigation Continuity**: Enable fluid user transitions between Dashboard, LiDAR Room Scanning (`RoomScanView`), and 3D Simulation (`Studio3DView`).
* **Architectural Modularity**: Maintain component folder cleanliness (`Features/Dashboard/Components/`) separating screen controllers from reusable cards and detail views.
* **Autonomous Testability**: Encapsulate mutation logic (rename, delete, layout creation) in `DashboardViewModel` so it can be verified via headless in-memory `ModelContainer` unit tests in sub-second test runs.
* **Apple HIG & Appearance**: Ensure system colors adapt dynamically to Dark and Light appearances.

## Considered Options

* **Option 1: Hybrid State Syncing**: Keep `@State [String]` for view rendering and manually synchronize changes back to SwiftData on view disappearance.
* **Option 2: Direct SwiftData Integration via `@Query` & `DashboardViewModel`**: Bind `DashboardView` directly to `@Query(sort: \Room.updatedAt, order: .reverse)` with mutation actions delegated to `DashboardViewModel`, while subviews are moved to `Components/`.

## Decision Outcome

Chosen option: **Option 2: Direct SwiftData Integration via `@Query` & `DashboardViewModel`**, because it guarantees consistency with the persistent store, eliminates data desynchronization bugs, and adheres to standard SwiftUI/SwiftData practices.

### Architectural Structure

1. **Root Screen (`DashboardView`)**:
   - Queries `[Room]` ordered by `updatedAt` descending.
   - Handles empty state when no rooms are present.
   - Presents `RoomScanView` via sheet on tap of the bottom floating action button (`+`).
   - Restores the toolbar link (`sun.max`) to `Studio3DView`.
   - Delegates room renaming and deletion to `DashboardViewModel`.
2. **Components (`Features/Dashboard/Components/`)**:
   - `LayoutCardView`: Renders room summary cards with swipe gestures for rename and delete actions.
   - `LayoutDetailsView`: Lists all `Layout` children belonging to a selected `Room`, with actions to inspect in `Studio3DView` or delete layouts.
3. **ViewModel (`DashboardViewModel`)**:
   - Encapsulates SwiftData context mutations: `renameRoom`, `deleteRoom`, `createLayout`, and `deleteLayout`.

### Positive Consequences

* Real scanned rooms automatically populate the dashboard.
* Deletion cascades correctly according to SwiftData relationship rules (`Room` $\rightarrow$ `Layout` $\rightarrow$ `Furniture`/`Light`).
* Both Empty State and Filled State are previews and unit tests can run against an in-memory `ModelContainer`.
* Subviews are organized cleanly under `Components/`.
* High-contrast, dynamic system colors prevent visual regressions in Dark Mode.

### Negative Consequences

* Views require a valid `ModelContext` in previews and execution environments (readily supplied via `ModelContainer.createInMemoryContainer()`).
