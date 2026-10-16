# Multi-Agent (Subagent + Orchestrator) Protocol

This rule governs the design, invocation, and coordination of multi-agent workflows within this repository.

---

## 1. The Orchestrator-Worker Architecture

```mermaid
flowchart TD
    User([Developer]) <--> Orchestrator[Lead Orchestrator Agent]
    
    subgraph Subagents["Specialized Subagents (Isolated Contexts)"]
        Researcher["researcher (Read-Only Apple Docs & Codebase Explorer)"]
        Critic["code-reviewer (Adversarial Critic)"]
        TestEngineer["test-engineer (Swift Testing & Fixtures)"]
        Refactorer["refactor-specialist (Clean Swift Code)"]
    end
    
    Orchestrator -->|invoke_subagent| Researcher
    Orchestrator -->|invoke_subagent| Critic
    Orchestrator -->|invoke_subagent| TestEngineer
    Orchestrator -->|invoke_subagent| Refactorer
    
    Researcher -->|findings| Orchestrator
    Critic -->|security, retain cycle, HIG review| Orchestrator
    TestEngineer -->|test fixtures & mocks| Orchestrator
    Refactorer -->|simplified code| Orchestrator
    
    Orchestrator --> Gatekeeper["Verification Gatekeeper (./scripts/verify.sh)"]
```

### Lead Orchestrator Responsibilities:
1. **Context Guardian**: Protects the main session context from massive Xcode build logs, Apple developer docs, or exploratory reads by delegating discovery to `researcher`.
2. **Decomposer**: Splits complex features into atomic sub-tasks with unambiguous Swift protocols and contracts.
3. **Adversarial Gate**: Submits proposed code diffs to `code-reviewer` before presenting them to the human.
4. **VCS Governor**: Maintains exclusive control over git commits, ensuring zero unauthorized commits and strict conventional commit formats.

---

## 2. Specialized Subagent Roster

| Subagent Role | Type / Mode | Capabilities & Tools | When to Invoke |
| :--- | :--- | :--- | :--- |
| **Researcher** | Read-Only | `view_file`, `grep_search`, `read_url_content`, `search_web` | Inspecting Apple developer documentation, discovering SwiftUI view modifiers, or exploring dependencies. |
| **Adversarial Critic** | Reviewer | Read-only tools + diff analysis | Reviewing diffs for retain cycles (`[weak self]`), SwiftData concurrency hazards, and Apple HIG violations. |
| **Test Engineer** | Full / Write | Read + Write + Test runner | Generating Swift Testing suites (`@Test`, `#expect`), in-memory container fixtures, and mock repositories. |
| **Refactor Specialist**| Full / Write | Read + Write + Verify | Extracting subviews, simplifying complex `@Model` definitions, and cleaning legacy code. |

---

## 3. Orchestration Workflows

### A. Parallel Fan-Out / Fan-In
When an epic contains independent research or test-writing tracks:
1. Orchestrator invokes subagents concurrently in a single `invoke_subagent` tool call.
2. Subagents execute in parallel in their own background processes.
3. As messages arrive reactively, Orchestrator merges insights and executes the implementation.

### B. Isolated Workspaces (`branch` / `share`)
- When testing experimental architectural refactors, dispatch subagents with `Workspace: 'branch'`.
- The subagent tests the hypothesis in an isolated git workspace without risking current working state.
- Once verified via `./scripts/verify.sh`, the orchestrator transfers the solution to the main tree.
