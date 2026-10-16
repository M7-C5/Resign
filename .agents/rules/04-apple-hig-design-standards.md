# Apple Human Interface Guidelines (HIG) & SwiftUI Design Standards

This rule governs all SwiftUI UI, layout, typography, and styling decisions within this codebase to ensure premier visual polish, accessibility, and native Apple feel.

---

## 1. Ergonomic Layout & Touch Targets

- **Minimum Hit Target**: Interactive elements (buttons, toggles, list rows) must maintain a minimum tappable area of **44 × 44 pt** (`.frame(minWidth: 44, minHeight: 44)` or `.contentShape(Rectangle())`).
- **Standard Spacing Grid**: Use Apple's 8pt grid system:
  - Small spacing: 8 pt
  - Standard spacing: 16 pt
  - Section spacing: 24–32 pt
- **Safe Area Insets**: Never clip text or actionable controls into the Dynamic Island, home indicator, or navigation bars. Use `.safeAreaPadding()` or `.ignoresSafeArea()` judiciously.
- **Card Containers**: Prefer native grouped surfaces:
  ```swift
  .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  ```

---

## 2. Dynamic Type & Typography Hierarchy

- **System Text Styles**: Always use semantic system fonts (`.largeTitle`, `.title`, `.headline`, `.body`, `.subheadline`, `.caption`) rather than fixed point sizes (`.font(.system(size: 14))`). Fixed sizes break accessibility when users adjust Dynamic Type scaling.
- **Multilingual & Truncation Safety**: Allow labels to wrap or dynamically scale:
  ```swift
  Text("Title")
      .font(.headline)
      .lineLimit(2)
      .minimumScaleFactor(0.85)
  ```

---

## 3. Dark Mode & High Contrast Symmetry

- **Semantic Colors**: Use semantic system colors (`Color.primary`, `Color.secondary`, `Color(uiColor: .systemBackground)`, `Color(uiColor: .secondarySystemGroupedBackground)`) instead of hardcoded hex values or literal `.black` / `.white`.
- **SF Symbols**: Use Apple's SF Symbols with semantic weights and hierarchical rendering:
  ```swift
  Image(systemName: "checkmark.seal.fill")
      .symbolRenderingMode(.hierarchical)
      .foregroundStyle(.tint)
  ```

---

## 4. Haptics & Sensory Feedback

- Trigger subtle haptic feedback on meaningful user interactions:
  ```swift
  .sensoryFeedback(.impact(weight: .light), trigger: isActionCompleted)
  ```
