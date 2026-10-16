# Apple & Swift Architectural Invariants

This rule governs the architectural patterns, state management, and modern Swift conventions within this repository.

---

## 1. Declarative SwiftUI & State Isolation

- **Observation Framework (`@Observable`)**: Use Swift's modern observation framework (`@Observable` class) for view state. Avoid legacy `ObservableObject` and `@Published` unless interoperating with pre-iOS 17 frameworks.
- **Single Source of Truth**: Keep `@State` private to the view that owns it. Pass read-only bindings (`@Binding`) or observable references down the hierarchy.
- **View Body Purity**: Keep `var body: some View` free of side effects, disk operations, or asynchronous calls. Use `.task { ... }` or `.onChange` to trigger lifecycle side effects.
- **View Hierarchy Decomposition**: Avoid monolithic view bodies exceeding 80 lines. Extract cohesive sub-components into private subviews or distinct View structs.

---

## 2. SwiftData Architecture & Persistence

- **Container Injection**: Rely on SwiftUI's `.modelContainer(sharedModelContainer)` established at the root `App` struct.
- **Context Boundaries (`ModelContext`)**:
  - Main thread UI updates must use `@Environment(\.modelContext)` on the `@MainActor`.
  - Heavy background batch operations must instantiate their own `ModelContext(modelContainer)` within background tasks.
- **Schema Migrations**: Define models cleanly using `@Model`. When changing schema fields, consider migration plans and default initializers to prevent crashes on existing user stores.
- **Memory & In-Memory Previews**: Provide an in-memory `ModelContainer` for SwiftUI Previews and Swift Testing to guarantee isolated, sub-second test execution.

---

## 3. Swift Concurrency & Thread Safety

- **Actor Isolation**: Annotate view-layer ViewModels and UI mutation functions with `@MainActor`.
- **Async/Await over Callbacks**: Use structured concurrency (`async/await`, `TaskGroup`) rather than closure completion handlers (`(Result<T, Error>) -> Void`).
- **Memory Retention Cycles**: When capturing `self` in escaping closures or observation callbacks, explicitly guard with `[weak self]` to eliminate retain cycles and memory leaks.
