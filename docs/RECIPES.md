# Agent Flight Simulator & Prompt Recipes (iOS / Swift)

This document provides battle-tested, turn-by-turn prompt recipes for directing AI agents (such as Antigravity) to build features, audit code, and fix bugs in this codebase without hallucination or context bloat.

---

## 🍳 Recipe 1: Contract-First Feature Scaffolding

### Objective
Create a new domain feature with complete interface separation, SwiftData `@Model`, in-memory tests, and a SwiftUI view.

### Prompt Template
```markdown
Please scaffold a new feature: [Feature Name] (e.g., Note / Expense / Goal).

Follow the contract-first protocol:
1. Model: Create a new `@Model` in `Resign/[ModelName].swift` with clean initializers.
2. In-Memory Testing: Add unit tests in `ResignTests/[ModelName]Tests.swift` using `ModelContainer.createInMemoryContainer()` to test creation, fetch, and deletion.
3. View & ViewModel: Create an `@Observable @MainActor` ViewModel and a declarative SwiftUI View adhering to Apple HIG (44x44pt touch targets, Dynamic Type, semantic colors).
4. Run `./scripts/verify.sh` to confirm compilation and zero test failures before declaring completion.
Do NOT commit to git.
```

---

## 🍳 Recipe 2: Autonomous Bug Fix & Self-Healing Loop

### Objective
Trigger the agent to diagnose a failing test or compiler error autonomously without copy-pasting terminal logs into the chat.

### Prompt Template
```markdown
Run `./scripts/verify.sh` to check for test or build errors.
If errors occur:
1. Inspect the stack trace and locate the failing file.
2. Read the source code around the error.
3. Implement the root-cause fix.
4. Re-run `./scripts/verify.sh` until all green.
Only report back when `./scripts/verify.sh` passes cleanly.
```

---

## 🍳 Recipe 3: Adversarial Code Review (Skill: `code-review`)

### Objective
Have an adversarial subagent review your staged or proposed changes before you merge or present them.

### Prompt Template
```markdown
Run an adversarial code review on the current git diff using the `code-review` skill.
Specifically scrutinize:
- Concurrency safety: Are ViewModels marked `@MainActor`? Are types Sendable?
- Memory retention: Are closures capturing `self` with `[weak self]` where appropriate?
- SwiftData boundaries: Is `ModelContext` isolated properly?
- Apple HIG: Are semantic system text styles used instead of hardcoded font sizes?
Provide a prioritized list of critical risks and recommendations.
```

---

## 🍳 Recipe 4: Apple HIG & Accessibility Polish (Skill: `ui-audit`)

### Objective
Audit and polish SwiftUI views for accessibility, Dynamic Type scaling, and Light/Dark appearance symmetry.

### Prompt Template
```markdown
Use the `ui-audit` skill on `[Path to SwiftUI View]`.
Verify:
1. Touch target geometry: Minimum 44x44pt on all interactive elements.
2. Dynamic Type: Semantic font styles (`.headline`, `.body`) without hardcoded point sizes.
3. System Colors: Semantic colors adapting properly between light and dark appearances.
4. Safe Area Insets: Content does not clip against the notch or home indicator.
Refactor any violations and verify with `./scripts/verify.sh`.
```

---

## 🚨 Emergency Circuit Breakers

If an agent ever gets stuck in a loop, paste one of these circuit breaker prompts:

### 🛑 Circuit Breaker 1: Infinite Test Loop Pause
```markdown
HALT TEST MODIFICATIONS. Do not modify the test assertions to make the suite pass. The test defines the contract. Re-read the requirements and fix only the implementation. Run `./scripts/verify.sh`.
```

### 🚨 Circuit Breaker 2: Multi-File Wandering Rollback
```markdown
STOP. You are touching unrelated files. Discard changes to everything except [target file], run `git status`, and run `./scripts/verify.sh`.
```
