---
name: ui-audit
description: Superpower skill for inspecting and enforcing SwiftUI layout ergonomics, Apple HIG compliance, Dynamic Type, and contrast symmetry.
---

# Superpower: Apple HIG & SwiftUI Layout Audit

Use this skill when auditing or refining UI components to ensure conformance with Apple design guidelines and accessibility standards.

## Audit Checklist:

### 1. Touch Target Geometry
- Ensure every tappable element meets the minimum **44 × 44 pt** touch target:
  ```swift
  .frame(minWidth: 44, minHeight: 44)
  .contentShape(Rectangle())
  ```

### 2. Spacing Rhythm & Padding
- Outer content gutters should use standard 16 pt or 20 pt margins:
  ```swift
  .padding(.horizontal, 20)
  .padding(.vertical, 16)
  ```
- Avoid cramped `padding(4)` or crowded list rows.

### 3. Dynamic Type Scalability
- Replace hardcoded font sizes (`.font(.system(size: 16))`) with semantic text styles:
  ```swift
  .font(.headline)
  .font(.body)
  .font(.caption)
  ```
- Verify text wrapping or `.minimumScaleFactor(...)` for localized strings.

### 4. Semantic Color & Dark Mode Contrast
- Use system semantic colors (`Color(uiColor: .systemBackground)`, `Color.secondary`, `Color.accentColor`) so views automatically adapt between Light Mode and Dark Mode.
- Verify contrast ratios in both appearances.
