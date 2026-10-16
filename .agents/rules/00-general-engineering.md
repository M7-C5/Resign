# Generalist Engineering Standards (Swift / Apple Ecosystem)

This document establishes the fundamental engineering rules for autonomous and paired AI agents working within this Swift / SwiftUI / SwiftData codebase.

## 1. Safety & VCS Discipline
- **Zero Premature Commits**: Never run `git commit` unless explicitly instructed by the user.
- **Atomic Commits**: Group related files into distinct, single-responsibility edits. Avoid mixing refactors with feature code.
- **Conventional Commits**: All commit messages must strictly adhere to the Conventional Commits specification (`feat:`, `fix:`, `docs:`, `build:`, `test:`, `refactor:`, `chore:`).
- **Non-Artifact Documentation**: All implemented features and systems must be documented within permanent repository files (`README.md` or `docs/*.md`) for persistent team viewing.
- **Documentation Preservation**: Preserve existing docstrings, licenses, comments, and architectural markers.

## 2. Defensive Interfaces & Modern Swift Type Safety
- **Strict Concurrency (`Sendable`)**: Ensure types shared across actor or task boundaries conform to `Sendable`. Eliminate data races at compile time.
- **Nil Safety & Immutability**: Prefer `let` over `var`. Favor non-optional types unless absence of value is an explicit domain state. Avoid force-unwrapping (`!`) except in test assertions or known invariant preconditions with descriptive comments.
- **Boundary Validation**: Validate external data (JSON, User Defaults, App Groups, Deep Links) using Swift `Decodable` structs with detailed coding keys and error handling.
- **Explicit Visibility**: Explicitly mark properties and methods as `private`, `fileprivate`, or `internal` to prevent leaky abstractions.

## 3. Pure Domain Core & Declarative Shell
- Keep domain models and business calculation engines pure (free of UIKit, AppKit, or view-lifecycle dependencies).
- Push side-effects (file I/O, SwiftData persistence mutations, network calls, notification scheduling) to dedicated service or repository layers.
- Pure domain models must be covered by Swift Testing (`@Test`, `#expect(...)`) with near-instant execution.

## 4. Progressive Task Breakdown
When tackling any feature:
1. **Spec**: Define data structures and requirements.
2. **Contract**: Write Swift protocols or `@Model` / struct declarations.
3. **Test Scaffolding**: Write failing Swift Testing test cases establishing the contract.
4. **Implementation**: Write the minimal code to satisfy tests.
5. **Self-Verification**: Run `./scripts/verify.sh` before declaring completion.
