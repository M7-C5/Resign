# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- feat(dashboard): build dashboard empty state (0fba429)
- feature(Lighting): added "add lighting source" feature (7242c42)
- feat(models): implement authentic room layout and lighting domain schema (3343fe0)
- feat(spatial): bundle mock room USDZ asset for lighting simulation (7bba77d)
- feat(assets): add procedural mock room generator with flat shading (979401d)
- feat(rules): establish feature delivery lifecycle and documentation invariants (ed764d8)
- feat(testing): add in-memory ModelContainer fixture and SwiftData unit tests (b4daaff)

### Fixed
- fix(preview): avoid Canvas initializer crash (c42ea43)
- fix(lighting-simulation): shape natural light to the window (5fbb493)

### Documentation
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

