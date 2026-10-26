# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- feat(navigation): add root home screen state switcher for scan launch and cancellation (0444327)
- feat(room-scan): update scanner overlay to top Cancel/Done navigation and remove redundant instruction banner (8298dd8)
- feat(room-scan): implement scan confirmation state machine, cancellation guard, and invalid scan validation (890e13b)
- feat(spatial): render two-wing geometry with open chair cutout for L-shaped desks (2781be9)
- feat(spatial): synthesize colliding table and credenza wings into L-shaped desks and apply category-aware wall snapping (fb61c0d)
- feat(spatial): preserve elevated surface objects and orthogonalize wall yaw alignment (630e39c)
- feat(spatial): extract masonry-to-masonry clear-span dimensions from opposing walls (2c660c7)
- feat(scanner): add room capture workflow with two-decimal metric display and realitykit preview (2e3e964)
- feat(spatial): implement clear-span floor dimension extraction and domain payload mapping (06cd811)
- feat(models): implement authentic room layout and lighting domain schema (3343fe0)
- feat(spatial): bundle mock room USDZ asset for lighting simulation (7bba77d)
- feat(assets): add procedural mock room generator with flat shading (979401d)
- feat(rules): establish feature delivery lifecycle and documentation invariants (ed764d8)
- feat(testing): add in-memory ModelContainer fixture and SwiftData unit tests (b4daaff)

### Documentation
- docs(adr): document L-shaped desk SAT wing synthesis and category-aware wall snapping in ADR 0010 (7efbe8a)
- docs(adr): update hybrid parametric shell architecture with surface elevation and clear-span pipeline (fa0fc42)
- docs(spatial): document room capture architecture, floor polygon contracts, and hybrid parametric shell adrs (50edd61)
- docs(architecture): define whiteboard domain schema and local-first persistence roadmap (1b90094)
- docs(adr): record architectural decision for mock USDZ reference environment (4da7ecf)
- docs(spatial): document mock room specifications and scene hierarchy (be1d834)
- docs: document vertical feature-slice architecture and invariants (a1ee548)
- docs: create comprehensive phased engineering roadmap (f149f5f)
- docs: document 3D spatial architecture, lighting engine, and ADR 0003 (3b068ef)
- docs: add architecture decision records and prompt recipe cookbook (3f0ca9d)
- docs: add agentic playbook, architecture blueprint, and changelog (178cddb)

### Tooling & Maintenance
- chore(release): update changelog for scan confirmation alert and lifecycle navigation (ebd395a)
- test(room-scan): verify confirmation alert transitions, scan cancellation, and invalid scan rejection (21ab947)
- chore(release): update changelog for L-shaped desk synthesis and category-aware wall snapping (de02b43)
- test(spatial): verify L-shaped desk wing merging and free-floating living room furniture preservation (c21b366)
- chore(changelog): update release changelog for masonry clear-span and surface elevation sanitization (4d2e552)
- test(spatial): add unit tests for masonry-to-masonry dimensions and elevated furniture sanitization (b8457b4)
- chore(changelog): update release changelog for spatial capture and clear-span dimension extraction (eb9fda6)
- test(spatial): add unit tests for clear-span floor dimensions, payload mapping, and scanner lifecycle (c2aa38f)
- chore(changelog): update release changelog for domain schema migration (ada76db)
- test(persistence): add room hierarchy persistence and model default initialization tests (20a21f7)
- chore(tooling): automate changelog generation from conventional commits (8d9466d)
- test(spatial): verify mock room hierarchy and required entities (3bab6e3)
- test: update smoke tests for scaffolded architecture (61df380)
- build: update verification script to strictly check exit codes (20ecbda)
- build(xcode): configure FastUnitTests and FullSuite test plans with shared scheme (322f3af)
- build: install native Conventional Commits git hook (7797521)
- build: implement autonomous verification and changelog scripts (156c0bc)
- build: establish modular engineering rules and superpower skills (929b639)
- build: configure agent constitution and lifecycle hooks (1cbaa5a)

