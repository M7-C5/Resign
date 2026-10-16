---
name: scaffold-module
description: Protocol for scaffolding a new Swift/SwiftUI feature or domain module following strict interface, testing, and implementation separation.
---

# Scaffold Module Skill (Swift / SwiftUI / SwiftData)

Use this skill when introducing a new feature domain to ensure contract-first development and architectural purity.

## 5-Step Scaffolding Procedure:

### Step 1: Model & Schema Definition
Define pure data models or SwiftData schemas:
```swift
@Model
final class FeatureItem {
    var id: UUID
    var title: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
```

### Step 2: Protocol Contracts
Define service or repository protocols isolating side-effects:
```swift
protocol FeatureRepositoryProtocol: Sendable {
    func fetchItems() async throws -> [FeatureItem]
    func save(item: FeatureItem) async throws
}
```

### Step 3: Test Scaffolding
Write unit tests using Swift Testing verifying domain invariants and in-memory container handling *before* building UI:
```swift
import Testing
@testable import Resign

@Suite("Feature Domain Tests")
struct FeatureTests {
    @Test func itemCreation() {
        let item = FeatureItem(title: "Test")
        #expect(item.title == "Test")
    }
}
```

### Step 4: UI & ViewModel Implementation
Implement declarative SwiftUI views and `@Observable` view models:
```swift
@Observable
@MainActor
final class FeatureViewModel {
    var items: [FeatureItem] = []
    // Business logic
}
```

### Step 5: Self-Verification Gate
Run `./scripts/verify.sh` to ensure clean build and passing tests before presenting the solution.
