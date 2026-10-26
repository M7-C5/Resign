# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- feat(dashboard): build LayoutCardView, build LayoutDetailsView, and add navigation from DashboardView to LayoutDetailsView (b47613a)
- Merge pull request #3 from M7-C5/feature/lighting (373f223)
- feat(dashboard): build dashboard empty state (0fba429)
- feature(Lighting): added "add lighting source" feature (7242c42)
- feat(models): implement authentic room layout and lighting domain schema (3343fe0)
- feat(spatial): bundle mock room USDZ asset for lighting simulation (7bba77d)
- feat(assets): add procedural mock room generator with flat shading (979401d)
- feat(rules): establish feature delivery lifecycle and documentation invariants (ed764d8)
- feat(testing): add in-memory ModelContainer fixture and SwiftData unit tests (b4daaff)

### Changed
- refactor(dashboard): integrate SwiftData models and decompose layout components (7f3f7a6)
- refactor(services): restore shared service placement (3afe8d0)
- refactor(studio3d): organize lighting code and remove dead views (173dd88)
- refactor(arch): scaffold vertical feature-slice architecture with skeleton modules (3419a7d)

### Fixed
- fix(dashboard): erase light symbol (0f52ca0)
- fix(changelog): include refactor commits in generated history (fcc84c3)
- fix(lighting): correct solar ephemeris coefficients (9542e10)
- fix(ci): use available iPhone simulator destination (afc82a5)
- fix(app): restore dashboard launch and studio route (107a72e)
- fix(preview): avoid Canvas initializer crash (c42ea43)
- fix(lighting-simulation): shape natural light to the window (5fbb493)

### Documentation
- docs(adr): document dashboard persistence and navigation architecture in ADR 0018 (e0348dd)
- docs(changelog): record PR review fixes (bbed95e)
- docs(adr): renumber lighting decisions after staging records (1e35072)
- docs(changelog): sync lighting branch entries (9de1e47)
- docs(changelog): record lighting simulation changes (ade6284)
- docs(architecture): define whiteboard domain schema and local-first persistence roadmap (1b90094)
- docs(adr): record architectural decision for mock USDZ reference environment (4da7ecf)
- docs(spatial): document mock room specifications and scene hierarchy (be1d834)
- docs: document vertical feature-slice architecture and invariants (a1ee548)
- docs: create comprehensive phased engineering roadmap (f149f5f)
- docs: document 3D spatial architecture, lighting engine, and ADR 0003 (3b068ef)
- docs: add architecture decision records and prompt recipe cookbook (3f0ca9d)
- docs: add agentic playbook, architecture blueprint, and changelog (178cddb)

### Tooling & Maintenance
- test(dashboard): add unit tests for SwiftData query and ViewModel mutations (96bbe92)
- chore(release): update changelog for App Store encryption compliance (039df6e)
- chore(build): set ITSAppUsesNonExemptEncryption to false for App Store compliance (689ba41)
- chore(release): update changelog for universal app icon (f0f23f0)
- chore(assets): add 1024x1024 universal app icon for CI validation (fb1ed4c)
- chore(release): update changelog for semantic pull request template (93fc68e)
- chore(tooling): add semantic pull request template for team workflow (96b0254)
- test(lighting-simulation): add simulator launch probe (519f57c)
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

