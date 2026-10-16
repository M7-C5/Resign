---
name: verify-suite
description: Comprehensive verification skill that runs the Xcode build and Swift unit tests and triages compiler or test errors autonomously.
---

# Verify Suite Skill (Xcode & Swift)

Use this skill when you have completed a code change or feature implementation and need to rigorously verify the health of the project.

## Workflow:
1. Run `./scripts/verify.sh`.
2. If `./scripts/verify.sh` succeeds:
   - Check if any new files need git status review (do NOT commit without user consent).
   - Report success with concise metrics (compilation status, unit tests passed).
3. If `./scripts/verify.sh` fails:
   - Locate the specific failure point:
     - **Swift Compiler Error**: Read compiler diagnostics, locate the offending file and line, inspect type mismatches or actor isolation (`@MainActor`).
     - **Swift Testing Failure**: Check `#expect(...)` assertion message and stack trace. Identify if the implementation is bugged or if test expectations need updating.
   - Edit the necessary files to address the root cause.
   - Re-run `./scripts/verify.sh`. Repeat until the build and test suite passes cleanly.
