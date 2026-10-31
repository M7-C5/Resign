# ADR 0032: Adapt Lighting Workspaces to the Available Window

- Status: Accepted
- Date: 2026-10-29
- Amends: [ADR 0011](0011-lightdraft-transient-edit-pattern.md), [ADR 0021](0021-room-north-alignment.md), [ADR 0024](0024-adaptive-ceiling-light-placement.md)

## Context

Lighting setup and orientation were stacked phone layouts, while simulation always reserved space for a bottom sheet. On iPad, controls stretched across the display, the plan stayed small, and the 3D preview was reduced even when a side inspector could fit. The compass also assumed portrait orientation.

## Decision Drivers

- Keep room content visible beside controls on sufficiently large windows.
- Support portrait, landscape, narrow Split View, short windows, and accessibility text.
- Preserve draft edits, saved light positions, selected fixtures, and camera state during resizing.
- Align compass readings to the interface shown in the current window.

## Considered Options

1. Detect iPad by device identity: rejected because window resizing and Split View change usable space.
2. Adapt to available window dimensions and text size: chosen.

## Decision Outcome

Use a shared window policy: side-by-side content when width is at least 900 points and height at least 500 points, except at accessibility text sizes. Bound the inspector to 320–380 points. Smaller windows use centered, scrollable stacks with bounded control widths.

Lighting setup and orientation keep state in their existing parent views while arranging room content and controls into columns. Simulation uses a side inspector on wide windows and the existing sheet on narrow windows. Switching presentation during resizing preserves the same live draft; only Cancel, Confirm, or an actual sheet dismissal ends editing. A side inspector does not apply bottom padding to the renderer. The camera compensates for a tall or narrow viewport while retaining the user's orbit and zoom values. iPad portrait windows narrower than 900 points use the larger stacked plan rather than squeezing it beside controls.

A window-scoped UIKit adapter reads interface orientation and maps landscape directions to the opposite physical heading orientation required by Core Location. A reference change before lock clears stale heading/filter/hold state and waits for fresh readings; an already locked calibration is preserved. No shared SwiftData schema changes are introduced.

## Consequences

- iPad layouts adapt to the actual window, including Split View and Stage Manager.
- Existing room coordinates and fixture persistence remain independent of presentation.
- Physical compass accuracy and LiDAR capture still require validation on supported hardware.

## Validation

Run `./scripts/verify.sh` for the simulator build and isolated unit tests. Cover full-size iPad windows, narrow and short windows, accessibility text, heading-orientation mapping, and calibration preservation. Inspect landscape and portrait iPad previews and verify Save/Cancel, sliders, center placement, and window resizing manually.

References: [Core Location heading orientation](https://developer.apple.com/documentation/corelocation/cllocationmanager/headingorientation), [interface versus device orientation](https://developer.apple.com/documentation/uikit/uiinterfaceorientation).
