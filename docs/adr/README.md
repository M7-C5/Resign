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

## How to Create a New ADR
1. Copy [template.md](template.md) to `docs/adr/NNNN-title-in-kebab-case.md`.
2. Follow MADR conventions: Context, Decision Drivers, Considered Options, Decision Outcome, and Consequences.
3. Update the Index above.
