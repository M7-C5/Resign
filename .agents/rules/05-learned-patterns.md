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
| **LP-005** | Spatial USDZ | USD Catmull-Clark Subdivision Trap | OpenUSD meshes default to `subdivisionScheme = "catmullClark"`, rounding rectangular bounding boxes into marshmallows. Architectural meshes must declare `uniform token subdivisionScheme = "none"`. | 2026-10-20 |
| **LP-006** | Workflow | ADR & Automated Changelog Mandate | New features, spatial assets, or architectural contracts require an ADR in `docs/adr/`. Changelogs must be generated via `scripts/changelog.sh`, with zero raw file paths in commit messages. | 2026-10-20 |
| **LP-007** | Markdown | Relative Repository Paths Only | Never embed host machine absolute paths (`/Users/...` or `file:///Users/...`) in repository markdown files. Always use clean relative project paths (`docs/foo.md`, `ROADMAP.md`). | 2026-10-20 |
| **LP-008** | SwiftData | Dynamic Query Navigation Destination Trap | Initializing `@Query` inside an inner struct inside `.navigationDestination(for:)` causes delayed or empty queries in iOS 17/18. Use synchronous `modelContext.fetch` on appear with hierarchy fallback instead. | 2026-10-27 |
| **LP-009** | Spatial LiDAR | Glass Surface & Truncated Floor Polygon Clamping | Near-infrared (940nm) LiDAR transmits through glass, and floor meshes stop short. Never clamp wall clear spans with `min(wallSpan, floorPoly)`; trust structural boundaries and endpoint extrusion. | 2026-10-27 |

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

---

### LP-005: USD Catmull-Clark Subdivision Trap
* **Context**: When generating procedural or box geometry in OpenUSD (`.usda` / `.usdz`), the USD standard default subdivision scheme is `catmullClark`. Renderers (SceneKit, RealityKit, QuickLook) recursively smooth 6-sided cubes into ellipsoids/marshmallows.
* **Bad Pattern**:
  ```usda
  # ❌ Renders as an egg / marshmallow
  def Mesh "Wall" {
      int[] faceVertexCounts = [4, 4, 4, 4, 4, 4]
      ...
  }
  ```
* **Good Pattern**:
  ```usda
  # ✅ Renders as a crisp, sharp architectural solid
  def Mesh "Wall" {
      uniform token subdivisionScheme = "none"
      ...
  }
  ```

---

### LP-006: Feature Implementation Tooling & ADR Discipline
* **Context**: Feature additions or spatial asset contracts must not bypass project tooling or architecture ledgers.
* **Rule**:
  1. Always author a corresponding ADR in `docs/adr/XXXX-title.md` for new architectural patterns, formats, or models.
  2. Always run `./scripts/changelog.sh` to update `CHANGELOG.md`—never hand-edit entries.
  3. Never mention raw file paths (e.g. `scripts/foo.py`) in commit messages or changelog lines. Describe domain capabilities instead.

---

### LP-008: Dynamic `@Query` in SwiftUI Navigation Destinations
* **Context**: When pushing a view via `.navigationDestination(for:)`, initializing `@Query` dynamically inside an inner container view struct (`_layouts = Query(filter: #Predicate { $0.id == targetId })`) frequently fails to evaluate or binds to an empty dataset in iOS 17/18, stranding the user on infinite loading progress views.
* **Bad Pattern**:
  ```swift
  // ❌ Fragile: dynamic @Query inside navigation destination struct init
  struct ContainerView: View {
      @Query private var items: [Item]
      init(id: UUID) {
          _items = Query(filter: #Predicate<Item> { $0.id == id })
      }
  }
  ```
* **Good Pattern**:
  ```swift
  // ✅ Deterministic: direct context query with model hierarchy fallback
  struct ContainerView: View {
      @Environment(\.modelContext) private var modelContext
      @State private var item: Item?

      var body: some View {
          Group {
              if let item { ActiveView(item: item) }
              else { ProgressView() }
          }
          .onAppear {
              let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
              self.item = try? modelContext.fetch(descriptor).first
          }
      }
  }
  ```

---

### LP-009: Spatial LiDAR Glass Reflections & Truncated Floor Mesh Clamping
* **Context**: iPhone LiDAR operates at ~940nm near-infrared, which passes through standard architectural glass without diffuse reflection. RoomPlan frequently classifies glass partition walls as windows or openings, or truncates the floor polygon 30–50 cm short due to ground reflection/refraction.
* **Bad Pattern**:
  ```swift
  // ❌ Fragile: Clamping opposing wall clear spans against truncated floor polygon
  let length = min(masonrySpan.length, floorPolygon.length) // Squeezes 4.1m down to 3.7m!
  ```
* **Good Pattern**:
  ```swift
  // ✅ Robust: Trust structural parallel wall spans and orthogonal endpoint extrusions
  // Include windows and openings as valid perimeter surfaces; never let floor mesh shrink walls
  let length = masonrySpan.length
  ```
