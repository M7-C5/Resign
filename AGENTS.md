# Agent Directives & Project Rules for Resign (iOS / Swift / SwiftUI)

1. **Commit & Changelog Standards**:
   - **Conventional Commits**: All commit messages must strictly follow the Conventional Commits specification (e.g., `feat:`, `fix:`, `docs:`, `test:`, `build:`, `refactor:`, `chore:`).
   - **No Raw File Paths in Commits or Changelogs**: Never mention raw file paths (e.g. `scripts/foo.py` or `Bar.swift`) in commit summaries or changelog bullet points. Use architectural concepts, domain entities, and descriptive component names.

2. **Autonomous Verification Gatekeeper**:
   - Before requesting human review, run `./scripts/verify.sh` to ensure clean compilation and all unit tests pass with zero errors.
   - **Performance Guard**: Never run UI performance metrics or full simulator cold-launch loops (`ResignUITests`) in fast verification turns. Keep unit tests (`ResignTests`) isolated and sub-second.

3. **Documentation & ADR Invariants**:
   - All implemented features, architectures, and capabilities must be documented in non-artifact repository markdown files (`README.md` and/or `docs/*.md`) for permanent viewing.
   - **Architectural Decision Records (ADRs)**: Any architectural contract, standardized reference environment, spatial schema, or significant design decision MUST be documented in a new ADR in `docs/adr/` and indexed in `docs/adr/README.md` (routine bug fixes and cosmetic adjustments bypass ADRs).
   - **Automated Changelog Tooling**: NEVER edit `CHANGELOG.md` manually. Always run `./scripts/changelog.sh` to compile conventional commits into the changelog.

4. **Mandatory Feature Implementation Lifecycle**:
   Whenever implementing any new feature, domain module, or architectural capability, execute this structured lifecycle:
   1. **Spec & Contract**: Define pure domain models/interfaces.
   2. **ADR (If Architectural)**: Author an ADR in `docs/adr/` ONLY when introducing new architectural contracts, spatial schemas, or persistence boundaries (routine fixes bypass ADRs).
   3. **Tests First**: Add unit tests in `ResignTests`.
   4. **Implementation**: Build minimal, clean code satisfying tests.
   5. **Verification**: Run `./scripts/verify.sh`.
   6. **Automated Changelog**: Run `./scripts/changelog.sh`.

5. **Domain Rules & Progressive Disclosure Index**:
   `AGENTS.md` is the primary entry point. When executing work in specific domains, the agent MUST read and apply the corresponding specialized rulebook in `.agents/rules/`:
   - **Generalist Engineering Standards**: `.agents/rules/00-general-engineering.md` (type safety, nil-safety, Sendable, pure domain core vs declarative shell).
   - **Verification Loop Protocol**: `.agents/rules/01-verification-loop.md` (autonomous test runner contracts, failure triaging).
   - **Apple & Spatial Architecture**: `.agents/rules/02-swift-apple-architecture.md` (SwiftData persistence boundaries, Swift Testing contracts, decoupled view adapters).
   - **Apple HIG & SwiftUI Ergonomics**: `.agents/rules/03-apple-hig-design-standards.md` (Dynamic Type, 44pt touch targets, WCAG contrast, haptics, dark/light symmetry).
   - **Living Post-Mortem Ledger**: `.agents/rules/04-learned-patterns.md` (empirical heuristics: LP-005 USD Catmull-Clark marshmallow trap, LP-008 dynamic `@Query` trap, LP-009 LiDAR glass wall reflections). When non-trivial framework quirks or spatial traps are solved, record them here.
