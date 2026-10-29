# Architecture Decision Records (ADRs)

This directory documents key architectural decisions for **Resign** using the [MADR](https://adr.github.io/madr/) (Markdown Architectural Decision Records) standard.

## Index of Decisions

- [ADR 0001: Record Architecture Decisions](0001-record-architecture-decisions.md)
- [ADR 0002: Test Partitioning and CPU Isolation](0002-test-partitioning-and-cpu-isolation.md)
- [ADR 0003: Core Architecture for Room Rearrangement and Lighting Simulation](0003-room-rearrangement-and-lighting-architecture.md)
- [ADR 0004: Standardized Mock USDZ Reference Environment for Simulation Testing](0004-standardized-mock-usdz-reference-environment.md)
- [ADR 0005: Authentic Whiteboard Domain Data Models and SwiftData Schema](0005-authentic-whiteboard-domain-data-models.md)
- [ADR 0006: Local-First SwiftData Persistence and CloudKit Synchronization Roadmap](0006-local-first-persistence-and-cloudkit-roadmap.md)
- [ADR 0007: RoomPlan LiDAR Capture and Geometric Sanitizer Pipeline](0007-roomplan-capture-and-sanitizer-pipeline.md)
- [ADR 0008: Arbitrary Polygon and Multi-Wall Room Geometry Engine](0008-arbitrary-polygon-and-multi-wall-room-geometry.md)
- [ADR 0009: Dimensional Precision, Oriented Bounding Box, and Plaster Wall Snapping](0009-dimensional-precision-and-plaster-snapping.md)
- [ADR 0010: Hybrid Native Parametric Room Shell and Sanitized Furniture Pipeline](0010-hybrid-native-parametric-room-and-sanitized-furniture.md)
- [ADR 0011: LightDraft Transient Value Type for Ceiling Grid Editing](0011-lightdraft-transient-edit-pattern.md)
- [ADR 0012: Lighting Simulation Modal Session](0012-lighting-simulation-modal-session.md)
- [ADR 0013: Mock Room Lighting Preview](0013-mock-room-lighting-preview.md)
- [ADR 0014: Window-Gated Mock Daylight](0014-window-gated-mock-daylight.md)
- [ADR 0015: Geographic Daylight in the New Room Renderer](0015-geographic-mock-daylight.md)
- [ADR 0016: Simulator Daylight Rendering Fallback](0016-simulator-daylight-fallback.md)
- [ADR 0017: Window-Shaped Direct Sunlight](0017-window-shaped-sunlight.md)
- [ADR 0018: Dashboard Persistence and Navigation Architecture](0018-dashboard-persistence-and-navigation-architecture.md)
- [ADR 0019: End-to-End View Navigation Architecture](0019-end-to-end-view-navigation-architecture.md)
- [ADR 0020: Simulate Layout-Saved Light Fixtures](0020-layout-lights-in-room-simulation.md)
- [ADR 0021: Calibrate Room North Before Light Placement](0021-room-north-alignment.md)
- [ADR 0022: Persist the Scanned Room Plan Frame](0022-persist-scanned-room-plan-frame.md)
- [ADR 0023: Render Lighting in the Selected Scanned Layout](0023-render-selected-scanned-layout-lighting.md)
- [ADR 0024: Adaptive Ceiling Light Placement](0024-adaptive-ceiling-light-placement.md)
- [ADR 0025: Interactive 3D Room Rearrangement and Scanned Room Pipeline](0025-interactive-3d-rearrangement-and-scanned-room-pipeline.md)

## How to Create a New ADR
1. Copy [template.md](template.md) to `docs/adr/NNNN-title-in-kebab-case.md`.
2. Follow MADR conventions: Context, Decision Drivers, Considered Options, Decision Outcome, and Consequences.
3. Update the Index above.
