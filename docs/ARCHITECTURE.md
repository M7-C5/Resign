# Resign Architecture Blueprint

This document details the system architecture, domain models, and technical design for **Resign**.

---

## 1. High-Level Architecture

Resign is built with modern Apple technologies:
- **Framework**: SwiftUI (Declarative UI)
- **Persistence**: SwiftData (`@Model`, `ModelContainer`, `ModelContext`)
- **Testing**: Modern Swift Testing framework (`import Testing`, `@Test`, `#expect`)
- **Language**: Swift 6 with Strict Concurrency (`Sendable`, `@MainActor`)

```
+-------------------------------------------------------------+
|                     SwiftUI View Layer                      |
|       (ContentView.swift, NavigationStack, Form / List)     |
+-------------------------------------------------------------+
                              |
                              v (Environment / ModelContext)
+-------------------------------------------------------------+
|                     Persistence Layer                       |
|               (SwiftData Item.swift, Schema)                |
+-------------------------------------------------------------+
                              |
                              v (In-Memory / SQLite Store)
+-------------------------------------------------------------+
|                ModelContainer / Disk Storage                |
+-------------------------------------------------------------+
```

---

## 2. Testing & Verification Boundaries

1. **Unit Tests (`ResignTests`)**:
   - Uses `import Testing`.
   - Uses in-memory `ModelContainer` for near-instant persistence tests.
   - Run on every verification turn via `./scripts/verify.sh`.

2. **UI Tests (`ResignUITests`)**:
   - Uses `import XCTest`.
   - Evaluates full application launch and interaction performance.
   - Partitioned away from the fast loop to eliminate simulator CPU overload (`./scripts/verify.sh --ui`).
