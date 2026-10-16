---
name: perf-audit
description: Superpower skill for measuring Swift compilation time, SwiftUI view re-render bottlenecks, and memory retain cycles.
---

# Superpower: Swift & iOS Performance Audit

Use this skill when auditing compile speeds, runtime responsiveness, view redraw counts, and memory allocations.

## Audit Checklist:

### 1. Swift Compilation Overhead
- Inspect complex expressions that cause type inference bottlenecks.
- Measure build time flags:
  ```bash
  -Xfrontend -warn-long-function-bodies=200
  -Xfrontend -warn-long-expression-type-checking=200
  ```

### 2. SwiftUI View Re-evaluation Bottlenecks
- Ensure `@Observable` models update only properties bound to active views to minimize unnecessary redraws.
- Avoid heavy computational logic inside computed `body` properties. Cache or compute asynchronously.

### 3. Memory Graph & Leaks
- Confirm closures capturing `self` in long-lived subscriptions or tasks declare `[weak self]`.
- Verify in-memory test suites tear down cleanly without retaining `ModelContainer` references.

### 4. Verification Execution Speed
- Keep `./scripts/verify.sh` under 10 seconds for incremental builds.
- Keep UI performance measurements strictly partitioned into manual or nightly runs.
