---
name: generate-changelog
description: Superpower skill for automatically inspecting git Conventional Commits and updating CHANGELOG.md adhering to Keep a Changelog.
---

# Superpower: Automated Changelog Generator

Use this skill when preparing a release, closing out a feature milestone, or updating project documentation to reflect recent changes.

## Procedure:

1. **Inspect Git History**:
   Run `./scripts/changelog.sh` to generate/preview categorized changes from recent Conventional Commits:
   ```bash
   ./scripts/changelog.sh
   ```

2. **Review Groupings**:
   - `feat:` -> Added
   - `fix:` -> Fixed
   - `perf:` -> Performance
   - `refactor:` -> Changed
   - `docs:` -> Documentation
   - `build:`, `test:`, `chore:` -> Tooling & Maintenance

3. **Update CHANGELOG.md**:
   - Move entries from `[Unreleased]` into the target release version header (e.g. `[1.0.0] - YYYY-MM-DD`).
   - Ensure format conforms strictly to [Keep a Changelog](https://keepachangelog.com/).

4. **Self-Verify**:
   - Run `./scripts/verify.sh` to ensure documentation changes introduced zero regressions.
