# Agent Directives & Project Rules for Resign (iOS / Swift / SwiftUI)

1. **Git Commit Protocol**:
   - NEVER commit changes to git until the user explicitly tells you to commit ("I will tell you to commit when it's time, I haven't tested it yet"). Only write code, build, and verify; wait for the user's go-ahead before executing any `git commit`.
   - All git commits must be separated into distinct, atomic commits—never make a monolithic commit.
   - **Conventional Commits**: All commit messages must strictly follow the Conventional Commits specification (e.g., `feat:`, `fix:`, `docs:`, `test:`, `build:`, `refactor:`, `chore:`).

2. **Autonomous Verification Gatekeeper**:
   - Before requesting human review, run `./scripts/verify.sh` to ensure clean compilation and all unit tests pass with zero errors.
   - **Performance Guard**: Never run UI performance metrics or full simulator cold-launch loops (`ResignUITests`) in fast verification turns. Keep unit tests (`ResignTests`) isolated and sub-second.

3. **Documentation Invariant**:
   - All implemented features, architectures, and capabilities must be documented in non-artifact repository markdown files (`README.md` and/or `docs/*.md`) for permanent viewing.

4. **Conversational Protocol**:
   - If the user prompt ends in a question, answer the question first and wait/align before starting work.
   - Actively challenge assumptions and offer candid, rigorous engineering feedback rather than being a yes-man.
