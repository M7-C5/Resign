<!-- PR Title Format: <type>(<scope>): <short summary in imperative mood> -->
<!-- Examples: feat(spatial): add L-shaped desk collision synthesis -->
<!--           fix(persistence): prevent container UUID rotation crash -->

## 📌 Summary / What
<!-- What does this PR change? Give a concise 2–3 sentence overview of the feature/fix and its impact on the system and user experience. -->

## 🎯 Why / Motivation
<!-- What problem does this solve? Reference linked issues or user stories (e.g., Closes #42, US1: Scan Completion & Confirmation). -->

## 🛠️ How / Technical Changes
<!-- Highlight architectural choices, math/spatial models, or edge cases handled. Group by component or domain module if extensive. -->
- **Component / Domain Entity**:
  - Description of change or algorithm (e.g., 2D OBB SAT, raycasting, SwiftUI view state).
- **SwiftData / Persistence Impact**:
  - [ ] **No Schema Changes** (Safe to merge without teammate impact)
  - [ ] **Additive / Non-Breaking** (New optional attributes or models)
  - [ ] **Breaking Migration** (Requires coordinated ModelContainer versioning — flag to team!)
- **Edge Cases & Error Handling**:
  - 

## 📸 Visuals & Spatial Artifacts (If Applicable)
<!-- Highly encouraged for SwiftUI, RealityKit, and Spatial pipeline changes. Drag and drop screenshots or screen recordings below. -->

| Before | After |
| :---: | :---: |
| *(Image/GIF)* | *(Image/GIF)* |

> [!NOTE]
> For spatial/LiDAR changes, attach or reference the sample USDZ / JSON fixture name used for validation.

## 🧪 How to Test
<!-- Step-by-step instructions for the reviewer on Simulator or physical LiDAR device. -->

### 1. Automated Verification
```bash
./scripts/verify.sh
```

### 2. Manual Reproduction / Verification Steps
1. Launch app onto...
2. Perform action...
3. Verify that...

## ✅ Reviewer & Author Checklist
- [ ] **Autonomous Verification**: `./scripts/verify.sh` compiles cleanly and all unit tests pass.
- [ ] **Unit Tests**: Isolated unit tests added or updated in `ResignTests` (sub-second execution).
- [ ] **Architecture & ADRs**: Updated or created ADR in `docs/adr/` if introducing new architectural contracts or spatial schemas.
- [ ] **Changelog**: Run `./scripts/changelog.sh` to compile conventional commits into `CHANGELOG.md` (no manual edits).
- [ ] **Teammate Boundary Check**: Verified changes do not break shared SwiftData models consumed by the Recommendation Engine or 3D Studio.
- [ ] **Path Sanitization**: Verified no machine-specific absolute file paths (`/Users/...`) exist in code or docs.
