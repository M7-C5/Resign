# Autonomous Verification Protocol

Every agent working on this codebase must autonomously self-verify before requesting human review or declaring completion.

## Verification Gatekeeper
The primary gatekeeper command is:
```bash
./scripts/verify.sh
```

This runs two sub-second / fast tiers:
1. **Xcode Build Compilation**: Compiles the `Resign` target with `xcodebuild build` targeting the iOS Simulator SDK. Catches Swift syntax, typing, and protocol conformance errors.
2. **Swift Unit Test Suite (`ResignTests`)**: Executes Swift Testing suites (`@Test`, `#expect(...)`) in headless simulator mode.

### CPU & Performance Isolation Invariant
- **Never trigger `ResignUITests` during standard verification loops**: Full UI test suites trigger cold simulator boots and `XCTApplicationLaunchMetric` loops that consume 100% of CPU for over a minute.
- UI tests are strictly reserved for manual verification runs via `./scripts/verify.sh --ui` or CI pipelines.

## Autonomous Triage Procedure
If `./scripts/verify.sh` fails:
1. **Read the exact error stack trace**: Extract filename, line number, and Swift error code or test assertion message.
2. **Do not guess or apply shotgun fixes**: Inspect the broken line in context using `view_file`.
3. **Fix the root cause**:
   - For compilation errors: check type mismatches, missing imports, or concurrency isolation warnings (`@MainActor`).
   - For test failures: verify if the test expectation or the domain implementation was incorrect.
4. **Re-run `./scripts/verify.sh`**: Confirm the fix resolves the issue with zero regressions.
5. **Only when all green**: Report outcome with evidence of verification.
