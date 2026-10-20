# Agent Directives & Project Rules for Resign (iOS / Swift / SwiftUI)

1. **Git Commit Protocol**:
   - NEVER commit changes to git until the user explicitly tells you to commit ("I will tell you to commit when it's time, I haven't tested it yet"). Only write code, build, and verify; wait for the user's go-ahead before executing any `git commit`.
   - All git commits must be separated into distinct, atomic commits—never make a monolithic commit.
   - **Conventional Commits**: All commit messages must strictly follow the Conventional Commits specification (e.g., `feat:`, `fix:`, `docs:`, `test:`, `build:`, `refactor:`, `chore:`).
   - **No Raw File Paths in Commits or Changelogs**: Never mention raw file paths (e.g. `scripts/foo.py` or `Bar.swift`) in commit summaries or changelog bullet points. Use architectural concepts, domain entities, and descriptive component names.
   - **Relative Project Paths Only**: In all repository markdown files, never write machine-specific absolute paths (e.g., `/Users/...` or `file:///Users/...`). Always use clean relative repository paths (e.g., `docs/ARCHITECTURE.md`).

2. **Autonomous Verification Gatekeeper**:
   - Before requesting human review, run `./scripts/verify.sh` to ensure clean compilation and all unit tests pass with zero errors.
   - **Performance Guard**: Never run UI performance metrics or full simulator cold-launch loops (`ResignUITests`) in fast verification turns. Keep unit tests (`ResignTests`) isolated and sub-second.

3. **Documentation & ADR Invariants**:
   - All implemented features, architectures, and capabilities must be documented in non-artifact repository markdown files (`README.md` and/or `docs/*.md`) for permanent viewing.
   - **Architectural Decision Records (ADRs)**: Any architectural contract, standardized reference environment, spatial schema, or significant design decision MUST be documented in a new ADR in `docs/adr/` and indexed in `docs/adr/README.md`.
   - **Automated Changelog Tooling**: NEVER edit `CHANGELOG.md` manually. Always run `./scripts/changelog.sh` to compile conventional commits into the changelog.

4. **Conversational Protocol**:
   - If the user prompt ends in a question, answer the question first and wait/align before starting work.
   - Actively challenge assumptions and offer candid, rigorous engineering feedback rather than being a yes-man.

5. **Mandatory Feature Implementation Lifecycle**:
   Whenever implementing any new feature, domain module, or reference asset, execute this strict 6-step lifecycle:
   1. **Spec & Contract**: Define pure domain models/interfaces.
   2. **ADR**: Create/update the corresponding ADR in `docs/adr/` if introducing architectural patterns or formats.
   3. **Tests First**: Add unit tests in `ResignTests`.
   4. **Implementation**: Build minimal, clean code satisfying tests.
   5. **Verification**: Run `./scripts/verify.sh`.
   6. **Automated Changelog**: Run `./scripts/changelog.sh`.
