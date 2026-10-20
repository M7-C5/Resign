# ADR 0003: Core Architecture for Room Rearrangement and Lighting Simulation

* Status: accepted
* Date: 2026-10-16
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign requires a robust spatial and photometric architecture to scan rooms with RoomPlan, generate 3D models, calculate real-world sunlight physics, allow Sims-style furniture repositioning, optimize layouts algorithmically, and project into 1:1 AR mode. We must formally establish the technical choices governing all 21 user flow steps.

## Decision Drivers

* Photorealistic lighting and real-time shadow casting in 3D and AR.
* Mathematical rigor in sunlight simulation and layout optimization.
* Touch ergonomics for furniture manipulation on mobile screens.
* Strict spatial accuracy requiring LiDAR hardware.

## Considered Options & Decisions

1. **3D Engine**: Chosen **RealityKit (`RealityView`)** over SceneKit due to native RoomPlan USDZ pipeline, modern PBR lighting, and seamless 1:1 ARKit integration.
2. **Hardware Gating**: Chosen **Strict LiDAR Requirement**. The app restricts spatial scanning strictly to LiDAR-equipped Pro devices (`RoomCaptureSession.isSupported`).
3. **Asset Strategy**: Chosen **Bundled Curated USDZ Catalog**. High-quality curated 3D assets are bundled and scaled non-uniformly to match RoomPlan bounding boxes.
4. **Sunlight Simulation**: Chosen **NOAA Solar Ephemeris Algorithm**. Calculates exact astronomical solar elevation and azimuth using CoreLocation GPS coordinates and compass orientation.
5. **Light Source Interface**: Chosen **2D Interactive Ceiling Grid (5×5)**. Provides immediate tactile control over fixture locations, lumens (0–2000 lm), and Kelvin color temperature.
6. **Layout Recommendation Engine**: Chosen **Hybrid Engine**. Deterministic pure Swift scoring engine for instant layout positioning + optional LLM explanations for human-readable design advice.
7. **Sims-Style Manipulation**: Chosen **Radial Contextual Action Menu + Floor Plane Dragging**. Direct floor plane ($Y=0$) translation with wall boundary collision detection.
8. **AR Presentation**: Chosen **1:1 Full-Scale Physical Immersion**. Projects virtual furniture directly into the physical room at true scale.
9. **Persistence**: Chosen **Hierarchical SwiftData Schema** (superseded by ADR 0005: `User` -> `Room` -> `Layout` -> `Furniture`, `Light`, `Insight`).

## Consequences

* Provides a unified, contract-first architectural foundation for all subsequent feature implementation.
* Pure Swift domain engines (Solar Ephemeris and Spatial Scoring) can be thoroughly unit tested in memory before any UI is built.
