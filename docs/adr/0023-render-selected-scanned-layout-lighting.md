# ADR 0023: Render Lighting in the Selected Scanned Layout

- Status: Accepted
- Date: 2026-10-27
- Amends: [ADR 0017](0017-window-shaped-sunlight.md), [ADR 0020](0020-layout-lights-in-room-simulation.md), [ADR 0022](0022-persist-scanned-room-plan-frame.md)

## Context

Studio 3D read the selected layout's fixtures and compass, but its renderer always loaded the bundled reference bedroom. Room shape, furniture, window direction, and lamp positions therefore differed from the scan.

## Decision Drivers

- Render the same saved layout selected from the dashboard.
- Keep the scan, orientation plan, light-placement grid, and simulation in one room coordinate frame.
- Keep geometry loading independent of time-slider edits.

## Considered Options

1. Continue using the reference model with saved lights: rejected because it misrepresents the scanned room.
2. Load the selected scan and normalize its coordinates: chosen because it preserves the native room shell and saved arrangement.

## Decision Outcome

Studio 3D creates an immutable scene descriptor from the selected layout. The renderer loads that layout's USDZ shell, disables native object wireframes, and adds its saved active furniture. The scan center, yaw, and floor height normalize the shell, furniture, windows, and fixtures into the same frame used by north alignment. Camera framing follows the loaded model bounds. A changed layout descriptor rebuilds the scene; lighting-slider edits update the existing rig.

When scan wall metadata is available, replace native wall meshes with aperture panels so solid-box parametric exports cannot block windows. Preserve the native floor and use translucent, non-shadow-casting window panes. Older models can recover wall spans from their native wall meshes when no saved snapshot is available. If the exported model cannot be loaded, reconstruct walls from saved wall segments and partition them around saved window and door apertures. Older records without wall metadata use their saved rectangular dimensions. The fallback floor is rectangular because a triangulated floor polygon is not stored. The bundled room remains available for explicit previews without a selected layout.

Each detected window supplies a position, size, and outward normal inferred from the nearest captured wall. Direct sunlight uses the dot product between the sun direction and that normal. Each window receives its own direct beam and diffuse fill; the room shares an interior sky-bounce source. A room with no detected windows receives no window daylight. The caption lists the detected facade directions combined with the saved compass bearing.

The Add Light Source screen uses the scanned plan. Its five rows and columns divide the normalized captured wall bounds into equal cells; the plan projection and simulated fixtures use those same bounds and cell centers. This prevents truncated summary dimensions from cropping the scan or compressing fixtures toward the center. When wall metadata is absent, both use the saved rectangular room dimensions. Clamp saved fixture height below the room ceiling. Preserve brightness, color temperature, and individual on/off state.

Adaptive candidate counts and position persistence are defined in [ADR 0024](0024-adaptive-ceiling-light-placement.md), which supersedes the fixed five-row/five-column placement lattice while preserving existing saved positions.

Artificial-light exposure is a render-only approximation: apply a 24× gain to nominal fixture lumens and a 75% unshadowed fill below the ceiling to compensate visually for missing indirect illumination. Tune low-output visibility against a 600-lumen saved fixture while preserving proportional output. Preview fixtures use the same nominal 1,080-lumen default as the editor. This does not change saved brightness, fixture locations, daylight intensity, or master/individual switch behavior, and is not a photometric calibration.

## Consequences

- Selected scans use their own geometry, arrangement, windows, and room dimensions in the lighting preview.
- The existing optional scan snapshot gains optional floor metadata. Older snapshots decode without it; the renderer can infer floor height from the loaded shell or grounded furniture.
- Facade normals are inferred from wall geometry. Concave layouts and incomplete scans can make the inference approximate.
- The solar reference date and geographic site remain the explicit Jakarta demonstration context. Light output and indirect bounce remain visual approximations rather than measured illuminance.

## Validation

Regression tests cover rotated and offset scan coordinates, floor alignment, room-scaled grid positions, the bundled native Room and Room-2 fixtures, missing-asset reconstruction without sample furniture, aperture cutouts, opposite window exposure at morning and afternoon, zero-window daylight shutdown, window captions across draft edits, older snapshot decoding, reopening and editing saved fixtures without duplication, deletion of all fixtures without affecting other layouts, and matching plan/fixture positions when wall bounds exceed summary dimensions. Run the fast verification suite for build and unit tests.
