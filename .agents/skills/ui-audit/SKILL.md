---
name: ui-audit
description: Superpower skill for inspecting and enforcing SwiftUI layout ergonomics, Apple HIG compliance, Dynamic Type, and contrast symmetry.
---

# Superpower: Apple HIG & SwiftUI Layout Audit

Use this skill when auditing or refining UI components to ensure strict compliance with Apple Human Interface Guidelines and accessibility invariants established in `.agents/rules/04-apple-hig-design-standards.md`.

## Active Audit Protocol:

1. **Touch Target Inspection**:
   - Check every button, toggle, and cell against the 44 × 44 pt minimum hit target.
   - Flag any touch element relying on raw text frame without `.contentShape(Rectangle())`.

2. **Typography & Dynamic Type**:
   - Grep for forbidden hardcoded sizes (e.g. `.system(size:)`). Replace with semantic styles (`.headline`, `.subheadline`, `.caption`).
   - Verify `minimumScaleFactor` or multiline limits on critical badges and labels.

3. **Color Symmetry & Contrast**:
   - Ensure zero hardcoded `.white` or `.black` text/backgrounds in standard views.
   - Verify views adapt symmetrically across Dark and Light appearances.

4. **Reference Rulebook**:
   - Consult `.agents/rules/04-apple-hig-design-standards.md` for complete spacing grids, continuous corner radius standards, and haptic feedback rules.
