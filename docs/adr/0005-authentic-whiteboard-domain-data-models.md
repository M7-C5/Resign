# ADR 0005: Authentic Whiteboard Domain Data Models and SwiftData Schema

* Status: accepted
* Date: 2026-10-20
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Early prototypes and placeholder models in Resign utilized generic names (`ScannedRoom`, `RoomLayout`, `FurniturePlacement`, `LightSource`, `RoomInsight`). However, the official product design and entity-relationship diagram (ERD) established on the project whiteboard define a cleaner, domain-native hierarchy:
`User` -> `Room` -> `Layout` -> (`Furniture`, `Light`, `Insight`), supplemented by `RoomOpening` for architectural openings (doors, windows, passageways).

We must formalize the SwiftData schema to align strictly with the whiteboard ERD while satisfying spatial computation requirements for Sims-style furniture placement, solar raycasting, artificial photometric calculations, and automated layout recommendations.

## Decision Drivers

* **Authentic Domain Alignment**: Direct correspondence between whiteboard architecture and SwiftData entity names (`User`, `Room`, `Layout`, `Furniture`, `Light`, `Insight`).
* **Spatial & Orientation Physics**: Support for 3D coordinates ($X, Y, Z$), Euler yaw rotation (`rotationYaw`), dimensions (length, width, height), compass heading, and GPS coordinates for solar ephemeris calculations.
* **Aperture & Raycast Modeling**: Dedicated `RoomOpening` entity linked to `Room` to track window and door apertures required for sunlight penetration and circulation clearance algorithms.
* **Interaction State Management**: First-class tracking for soft-deleted / staged furniture (`isArchived`) and active light states (`isOn`).
* **SwiftData Macro Compatibility**: Avoid SwiftData runtime and macro collisions with reserved compiler symbols (e.g. `description` collision with `CustomStringConvertible` resolved by using `detail`).

## Considered Options

1. **Option 1: Retain Over-Engineered Names (`ScannedRoom`, `RoomLayout`, etc.)**: Kept existing names and adapted them. Rejected because it violates developer whiteboard intent and adds cognitive overhead.
2. **Option 2: Authentic Whiteboard Schema with Spatial Enhancements**: Implement the exact whiteboard entity names (`User`, `Room`, `Layout`, `Furniture`, `Light`, `Insight`), add `RoomOpening`, and include necessary simulation attributes (`rotationYaw`, `category`, `isArchived`, `isOn`, `detail`).

## Decision Outcome

Chosen option: **Option 2: Authentic Whiteboard Schema with Spatial Enhancements**.

### Entity Schema Summary

1. **`Room`** (Root Domain Entity):
   - `id: UUID`, `name: String`, `longitude: Double`, `latitude: Double`, `compass: Double`, `length: Float`, `width: Float`, `height: Float`, `createdAt: Date`, `updatedAt: Date`
   - Relationships: `layouts: [Layout]` (cascade delete), `openings: [RoomOpening]` (cascade delete)
2. **`RoomOpening`**:
   - `id: UUID`, `type: String` ("window", "door", "opening"), `posX: Float`, `posY: Float`, `posZ: Float`, `width: Float`, `height: Float`
   - Relationships: `room: Room?`
3. **`Layout`**:
   - `id: UUID`, `name: String`, `usdzURL: URL?`, `createdAt: Date`, `updatedAt: Date`
   - Relationships: `room: Room?`, `furnitures: [Furniture]` (cascade delete), `lights: [Light]` (cascade delete), `insights: [Insight]` (cascade delete)
4. **`Furniture`**:
   - `id: UUID`, `name: String`, `category: String`, `texture: String`, `positionX: Float`, `positionY: Float`, `positionZ: Float`, `rotationYaw: Float`, `length: Float`, `width: Float`, `height: Float`, `isArchived: Bool`, `usdzURL: URL?`
   - Relationships: `layout: Layout?`
6. **`Light`**:
   - `id: UUID`, `name: String`, `coordinateX: Float`, `coordinateY: Float`, `elevationZ: Float`, `brightness: Float`, `colorTemp: Int`, `isOn: Bool`
   - Relationships: `layout: Layout?`
7. **`Insight`**:
   - `id: UUID`, `title: String`, `type: String` ("+" or "-"), `detail: String`
   - Relationships: `layout: Layout?`

### Consequences

* Clean, expressive domain models mapped directly to SwiftUI views and SwiftData `@Query` properties.
* Strict cascade deletion rules ensure orphaned sub-entities are cleaned up automatically when parent rooms or layouts are deleted.
* Rapid in-memory unit testing via `ModelContainer.createInMemoryContainer()` verifies schema consistency in sub-second verification runs.
