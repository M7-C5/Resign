---
name: code-review
description: Superpower skill for conducting an adversarial code review on git diffs or proposed Swift/SwiftUI changes before user presentation.
---

# Superpower: Adversarial Code Review (Swift / Apple)

Use this skill to critically review code changes, identify hidden defects, and ensure enterprise-grade code quality before presenting work to the developer.

## Review Checklist:

### 1. Concurrency & Memory Safety
- Are actor boundaries respected? Are ViewModel or UI-bound classes annotated with `@MainActor`?
- Are escaping closures and tasks capturing `self` without `[weak self]` when retain cycles are possible?
- Are Swift types crossing task boundaries properly conforming to `Sendable`?

### 2. SwiftData & Persistence Discipline
- Is `ModelContext` manipulated on the appropriate actor/thread?
- Are model relationships properly marked with delete rules (e.g. `.cascade`, `.nullify`)?
- Are schema modifications covered with fallback initializers or migration plans?

### 3. Apple Human Interface Guidelines & Layout Ergonomics
- Are touch targets at least 44 × 44 pt?
- Are semantic fonts (`.headline`, `.body`) used instead of hardcoded sizes to support Dynamic Type?
- Are semantic colors used to ensure contrast in both Light and Dark Modes?
- Are views decomposed cleanly to prevent excessive `body` re-evaluations?

### 4. Verification & Testing
- Does every new model, view model, or service have an accompanying Swift Testing suite (`@Test`, `#expect`)?
- Did `./scripts/verify.sh` pass with zero compiler warnings or errors?
