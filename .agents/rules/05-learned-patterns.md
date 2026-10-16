# Dynamic Learning Memory & Living Post-Mortem Ledger

> **Purpose**: This living rule file captures empirical developer corrections, Xcode / Swift quirks, and project post-mortems.
> **Loading Invariant**: In accordance with the **Progressive Disclosure Principle**, Antigravity and subagents consult this ledger before proposing code changes.

---

## 📋 Learned Patterns Index

| ID | Category | Title | Heuristic Summary | Date Added |
| :--- | :--- | :--- | :--- | :--- |
| **LP-001** | Verification | UI Test Performance Isolation | `ResignUITests` boots an iOS Simulator clone and runs `XCTApplicationLaunchMetric`, taking >70s and 100% CPU. Run only `ResignTests` in the fast loop. | 2026-10-16 |
| **LP-002** | Swift Testing | Modern `@Test` API | Use Swift Testing (`import Testing`, `@Test`, `#expect(...)`) rather than legacy `XCTestCase` for unit tests. | 2026-10-16 |
| **LP-003** | SwiftData | In-Memory Testing Containers | When testing SwiftData models, instantiate `ModelConfiguration(isStoredInMemoryOnly: true)` to avoid persistent disk state between tests. | 2026-10-16 |
| **LP-004** | SwiftUI HIG | Dynamic Type Safety | Never hardcode font point sizes; always use semantic `.font(.headline)` styles to guarantee Dynamic Type compliance. | 2026-10-16 |

---

## 🔍 Detailed Heuristic Profiles

### LP-001: UI Test Performance Isolation
* **Context**: Running `xcodebuild test` without target filtering executes `ResignUITests.testLaunchPerformance()`, triggering cold simulator launches and CPU spikes.
* **Bad Pattern**:
  ```bash
  # ❌ Triggers 100% CPU simulator metric loops for over a minute
  xcodebuild test -scheme Resign
  ```
* **Good Pattern**:
  ```bash
  # ✅ Sub-second unit tests only
  xcodebuild test -scheme Resign -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ResignTests
  ```

---

### LP-002: Modern Swift Testing
* **Context**: Swift 6 introduces Swift Testing as the primary modern testing framework.
* **Good Pattern**:
  ```swift
  import Testing
  @testable import Resign

  struct ResignTests {
      @Test func itemCreation() async throws {
          let item = Item(timestamp: Date())
          #expect(item.timestamp <= Date())
      }
  }
  ```
