# The Agentic Software Engineering Playbook (Apple & Swift Edition)

This playbook outlines how autonomous AI agents collaborate on the **Resign** iOS project.

---

## 1. Context Hierarchy & Progressive Disclosure

```
                       +------------------------------------------+
                       |  5. Progressive Superpowers & Skills     |
                       |     (.agents/skills/*)                   |
                       +------------------------------------------+
                       |  4. Living Swift Protocols & Schemas     |
                       |     (SwiftData @Model, Protocols)        |
                       +------------------------------------------+
                       |  3. Autonomous Self-Verification Loop    |
                       |     (./scripts/verify.sh: build & test)  |
                       +------------------------------------------+
                       |  2. Modular Progressive Rules            |
                       |     (.agents/rules/*)                    |
                       +------------------------------------------+
                       |  1. Root Constitution & Safety Bounds    |
                       |     (AGENTS.md, Git Discipline)          |
                       +------------------------------------------+
                                 AGENT CONTEXT PYRAMID
```

---

## 2. Core Axioms for iOS Agentic Development

1. **Sub-Second Test Partitioning**:
   - Compiling and executing unit tests (`ResignTests`) takes ~2–4 seconds.
   - UI automation (`ResignUITests`) boots physical simulator clones and benchmarks launch times over 70+ seconds.
   - **Never run UI performance benchmarks on fast turns**. Use `./scripts/verify.sh` for fast inner-loop verifications.

2. **Strict Git Discipline**:
   - Agents **never** run `git commit` without explicit permission from the developer.
   - Every commit must be atomic and follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`).

3. **Adversarial Code Review**:
   - Before presenting code diffs, agents invoke the `code-review` superpower to verify retain cycles (`[weak self]`), actor isolation (`@MainActor`), and Apple HIG compliance.

---

## 3. Developer & Agent Command Quick Reference

| Action | Command | Purpose |
| :--- | :--- | :--- |
| **Fast Verification** | `./scripts/verify.sh` | Compiles scheme + runs Swift unit tests (~3s) |
| **Full UI Verification** | `./scripts/verify.sh --ui` | Runs compilation + unit tests + full UI launch benchmarks |
| **Changelog Generator**| `./scripts/changelog.sh`| Categorizes conventional commits for `CHANGELOG.md` |
| **Install Git Hooks** | `./scripts/install-hooks.sh` | Configures git hooks for Conventional Commits & path sanitization |
| **Build Only** | `xcodebuild build -scheme Resign -destination 'generic/platform=iOS Simulator'` | Immediate syntax / type checking |
