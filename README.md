# Resign — iOS Application & Agentic Engineering Environment

> Modern native iOS application built with **SwiftUI**, **SwiftData**, and **Swift Testing**, engineered for autonomous AI agent collaboration with **Antigravity**.

---

### 📖 Table of Contents
- [Architecture & Tech Stack](#architecture--tech-stack)
- [Agentic Workflow & Safety Directives](#agentic-workflow--safety-directives)
- [Superpower Skills Matrix](#superpower-skills-matrix)
- [Verification & Quality Loop](#verification--quality-loop)
- [Git & Conventional Commits Protocol](#git--conventional-commits-protocol)
- [Documentation & Guides](#documentation--guides)

---

## 🛠️ Architecture & Tech Stack

- **UI Framework**: SwiftUI (Declarative, Apple HIG compliant)
- **Persistence**: SwiftData (`@Model`, `ModelContainer`)
- **Unit Testing**: Modern Swift Testing (`import Testing`, `@Test`, `#expect`)
- **UI Testing**: XCTest (`ResignUITests`)
- **Target OS**: iOS 17+ (iPhone & iPad)
- **Concurrency**: Swift 6 Strict Concurrency (`Sendable`, `@MainActor`)

---

## 🤖 Agentic Workflow & Safety Directives

This project implements the **Agentic Software Engineering System** adapted from the [Agentic-Workflow](file:///Users/verzional/Home/Zed/Personal/Agentic-Workflow/README.md) foundation:

1. **Root Constitution ([`AGENTS.md`](file:///Users/verzional/Home/Xcode/Resign/AGENTS.md))**:
   - Zero unauthorized git commits. Commit only when explicitly directed by the human developer.
   - Atomic commits adhering to the Conventional Commits specification.
   - Non-artifact documentation invariant (`README.md`, `docs/*.md`).

2. **Modular Rule Base ([`.agents/rules/`](file:///Users/verzional/Home/Xcode/Resign/.agents/rules/))**:
   - [`00-general-engineering.md`](file:///Users/verzional/Home/Xcode/Resign/.agents/rules/00-general-engineering.md): Defensive typing, Sendable safety, pure domain core.
   - [`01-verification-loop.md`](file:///Users/verzional/Home/Xcode/Resign/.agents/rules/01-verification-loop.md): Sub-second verification gatekeeper with CPU isolation.
   - [`02-swift-apple-architecture.md`](file:///Users/verzional/Home/Xcode/Resign/.agents/rules/02-swift-apple-architecture.md): SwiftUI state, SwiftData boundaries, actor isolation.
   - [`03-multi-agent-orchestration.md`](file:///Users/verzional/Home/Xcode/Resign/.agents/rules/03-multi-agent-orchestration.md): Lead orchestrator and specialized subagents.
   - [`04-apple-hig-design-standards.md`](file:///Users/verzional/Home/Xcode/Resign/.agents/rules/04-apple-hig-design-standards.md): Apple HIG ergonomics, Dynamic Type, 44×44pt touch targets.
   - [`05-learned-patterns.md`](file:///Users/verzional/Home/Xcode/Resign/.agents/rules/05-learned-patterns.md): Living post-mortem memory ledger.

---

## ⚡ Superpower Skills Matrix

Defined under [`.agents/skills/`](file:///Users/verzional/Home/Xcode/Resign/.agents/skills/):

| Skill Name | Description | Trigger |
| :--- | :--- | :--- |
| **`verify-suite`** | Runs `./scripts/verify.sh` and triages compiler or test errors autonomously. | After completing any code modification. |
| **`code-review`** | Adversarial review for memory retain cycles, concurrency data races, and Apple HIG violations. | Before presenting code diffs to human. |
| **`scaffold-module`**| 5-step contract-first scaffolding for SwiftUI features and SwiftData models. | When designing a new domain or view. |
| **`generate-changelog`**| Inspects git Conventional Commits and automatically updates `CHANGELOG.md`. | Before releasing or tagging a milestone. |
| **`ui-audit`** | Audits SwiftUI layout hierarchy, touch targets, contrast symmetry, and Dynamic Type. | When polishing views. |
| **`security-audit`** | Scans Keychain usage, App Transport Security, entitlements, and permissions. | Prior to production release. |
| **`perf-audit`** | Evaluates Swift compile times and view body re-render bottlenecks. | On performance investigations. |

---

## 🧪 Verification & Quality Loop

### Quick Start
To run the fast verification loop (build + unit tests):
```bash
./scripts/verify.sh
```

To run the complete suite including UI performance benchmarks:
```bash
./scripts/verify.sh --ui
```

---

## 📝 Git & Conventional Commits Protocol

All commits in this repository must use Conventional Commits:
- `feat:` A new user-facing feature
- `fix:` A bug fix
- `docs:` Documentation updates
- `test:` Adding or updating unit tests
- `refactor:` Code restructuring without behavior changes
- `perf:` Performance optimizations
- `build:` / `chore:` Tooling, scripts, and build system configuration

---

## 📚 Documentation & Guides

- [Agentic Playbook](file:///Users/verzional/Home/Xcode/Resign/docs/AGENTIC_PLAYBOOK.md)
- [Architecture Blueprint](file:///Users/verzional/Home/Xcode/Resign/docs/ARCHITECTURE.md)
- [Architecture Decision Records (ADRs)](file:///Users/verzional/Home/Xcode/Resign/docs/adr/README.md)
- [Flight Simulator & Prompt Recipes](file:///Users/verzional/Home/Xcode/Resign/docs/RECIPES.md)
- [Living Changelog](file:///Users/verzional/Home/Xcode/Resign/CHANGELOG.md)
