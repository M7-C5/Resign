# ADR 0002: Test Partitioning and CPU Isolation

* Status: accepted
* Date: 2026-10-16
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Executing `xcodebuild test` without target filtering executes `ResignUITests.testLaunchPerformance()`, which boots simulator clones and measures cold launch metrics for over 70 seconds, consuming 100% of all host CPU cores.

During active agentic pair-programming, fast verification (`./scripts/verify.sh`) is executed frequently. Excessive CPU overhead degrades developer workstation responsiveness and exhausts context timeouts.

## Decision Drivers

* Inner-loop verification must remain fast (< 10 seconds incremental).
* Host machine resources (CPU/battery) must not be saturated during active typing and verification.
* UI and launch benchmarks must still be testable on demand and in CI.

## Considered Options

* Option 1: Test Plan Partitioning (`FastUnitTests.xctestplan` vs `FullSuite.xctestplan`) and `./scripts/verify.sh` flag gating.
* Option 2: Deleting `ResignUITests` entirely.
* Option 3: Leaving all tests in the default scheme without filtering.

## Decision Outcome

Chosen option: Option 1.
We created two Xcode test plans:
1. `FastUnitTests.xctestplan` (default in `Resign.xcscheme`), executing only fast `ResignTests` Swift unit tests.
2. `FullSuite.xctestplan`, executing both unit tests and UI benchmarks via `./scripts/verify.sh --ui`.

### Positive Consequences
* Inner-loop verification executes quickly with zero CPU spikes.
* Parity between Xcode UI (Cmd+U) and CLI (`./scripts/verify.sh`).
* Full UI regression testing is preserved for manual runs and CI.
