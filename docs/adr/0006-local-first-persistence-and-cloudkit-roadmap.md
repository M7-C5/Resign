# ADR 0006: Local-First SwiftData Persistence and CloudKit Synchronization Roadmap

* Status: accepted
* Date: 2026-10-20
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign's domain models (`User`, `Room`, `RoomOpening`, `Layout`, `Furniture`, `Light`, `Insight`) require persistence and future multi-device synchronization. Connecting SwiftData directly to CloudKit (`ModelConfiguration(cloudKitDatabase: .private)`) introduces strict architectural constraints:
1. **Schema Rigidness**: All stored properties must declare inline default values or be optional.
2. **Identity & Uniqueness**: Client-side `@Attribute(.unique)` is forbidden in CloudKit-synced SwiftData containers.
3. **Sandbox File Traps**: Local file `URL` instances do not sync to remote file sandboxes without using `CKAsset` (`Data`).
4. **Development Friction**: Live CloudKit synchronization locks schemas against destructive local iteration, requires active Apple Developer Team iCloud capability provisioning, and slows down automated test cycles.

We need an architectural strategy that maximizes developer iteration velocity on the core 3D simulation, photometric calculation, and layout generation engines while remaining seamlessly forward-compatible with CloudKit sync when ready.

## Decision Drivers

* **Rapid Prototyping Velocity**: Instant sub-second test execution and schema agility without remote iCloud provisioning roadblocks.
* **Zero Rewrite Migration**: SwiftData models must adhere to CloudKit schema validation rules immediately so flipping to CloudKit in the future requires zero model refactoring.
* **Authentic Domain Alignment**: Focuses on core domain entities (`Room`, `RoomOpening`, `Layout`, `Furniture`, `Light`, `Insight`), establishing `Room` as the true root entity and eliminating vestigial `User` wrappers.
* **Temporal Sorting & Determinism**: First-class tracking for creation and modification timestamps (`createdAt`, `updatedAt`).

## Considered Options

1. **Option 1: Immediate Live CloudKit Synchronization**: Enable `cloudKitDatabase: .private` immediately. Rejected due to development friction, iCloud provisioning overhead, and premature optimization.
2. **Option 2: Unconstrained Local Schema Without CloudKit Forward-Compatibility**: Build models ignoring CloudKit rules. Rejected because retrofitting CloudKit later causes breaking migrations and massive schema rewrites.
3. **Option 3: Local-First Persistence with CloudKit-Hardened Schema Invariants**: Run SwiftData locally during active feature development while enforcing all CloudKit structural invariants (inline defaults, optional relationships, timestamps, no unique constraints).

## Decision Outcome

Chosen option: **Option 3: Local-First Persistence with CloudKit-Hardened Schema Invariants**.

### Technical Rules Applied

1. **Root Entity (`Room`)**: Removed the artificial `User` entity. In local-first mode (and in future CloudKit private stores), the device owner is the implicit tenant. `Room` is queried directly via `@Query`.
2. **Inline Default Values**: Every stored scalar property in `Room`, `RoomOpening`, `Layout`, `Furniture`, `Light`, and `Insight` declares an inline default value, satisfying CloudKit schema validation without runtime crashes.
3. **Temporal Metadata**: Added `createdAt: Date = Date()` and `updatedAt: Date = Date()` to `Room` and `Layout` for dashboard recency sorting and future sync conflict tie-breaking.
4. **Relational Integrity**: All to-one inverse relationships remain optional (`Room?`, `Layout?`).
5. **Local Container Execution**: `ModelContainer` in `ResignApp.swift` initializes with `isStoredInMemoryOnly: false` against the local SQLite store, deferring remote iCloud container linking to a dedicated release milestone.

### Consequences

* Fast, deterministic local unit testing via `ModelContainer.createInMemoryContainer()` with zero network dependency.
* Instant dashboard queryability by sorting on `createdAt` or `updatedAt`.
* Clean, frictionless future activation of CloudKit private sync when multi-device testing begins.
