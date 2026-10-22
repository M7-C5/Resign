# Architecture Decision Records (ADRs)

This directory documents key architectural decisions for **Resign** using the [MADR](https://adr.github.io/madr/) (Markdown Architectural Decision Records) standard.

## Index of Decisions

- [ADR 0001: Record Architecture Decisions](0001-record-architecture-decisions.md)
- [ADR 0002: Test Partitioning and CPU Isolation](0002-test-partitioning-and-cpu-isolation.md)
- [ADR 0003: Core Architecture for Room Rearrangement and Lighting Simulation](0003-room-rearrangement-and-lighting-architecture.md)
- [ADR 0004: Standardized Mock USDZ Reference Environment for Simulation Testing](0004-standardized-mock-usdz-reference-environment.md)
- [ADR 0005: Authentic Whiteboard Domain Data Models and SwiftData Schema](0005-authentic-whiteboard-domain-data-models.md)
- [ADR 0006: Local-First SwiftData Persistence and CloudKit Synchronization Roadmap](0006-local-first-persistence-and-cloudkit-roadmap.md)
- [ADR 0007: LightDraft Transient Value Type for Ceiling Grid Editing](0007-lightdraft-transient-edit-pattern.md)

- [ADR 0008: Lighting Simulation Modal Session](0008-lighting-simulation-modal-session.md)

## How to Create a New ADR
1. Copy [template.md](template.md) to `docs/adr/NNNN-title-in-kebab-case.md`.
2. Follow MADR conventions: Context, Decision Drivers, Considered Options, Decision Outcome, and Consequences.
3. Update the Index above.
