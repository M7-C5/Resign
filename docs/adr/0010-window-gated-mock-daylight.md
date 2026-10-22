# ADR 0010: Window-Gated Mock Daylight

- Status: accepted
- Date: 2026-10-22

## Context

The mock studio previously illuminated the room with unshadowed directional daylight and time-varying ambient illumination. Hidden enclosure surfaces allowed unrealistic illumination through the dollhouse cutaway.

## Decision

Retain the ceiling, west wall, south wall segments, and door as active shadow-casting geometry in category 2. The viewing camera sees category 1 only; daylight includes both categories (mask 3). Restore the USD ceiling visibility for shadow rendering. Keep the east wall opening and window frame geometry intact. Glass does not cast an opaque shadow because SceneKit shadow maps do not model its light transmission.

Place the directional source east of the room, aimed down through the window. Enable forward shadow mapping with a 2048-square map and a small bias. Retain a constant ambient intensity of 60 for readability, independent of time. Time changes only the direct daylight intensity; sample artificial fixtures remain independently controlled.

## Limitations

This is a fixed-direction visual approximation, not geographic sun tracking, glass refraction, global illumination, or calibrated photometry. Ambient is a small display fill and not simulated daylight bounce. Exterior faces can still receive sunlight; direct illumination inside is restricted by the enclosure. This supersedes the unshadowed daylight and ambient curve in ADR 0009.

## Validation

Scene tests verify that the cutaway enclosure remains active, camera and daylight masks differ as required, and glass does not block direct light. Offscreen rendering with artificial lights disabled shows a window-shaped patch with mullion shadows. A temporary opaque panel closing the window removes the patch; the panel is only used for verification and is not added to the app or asset.
