# ADR 0015: Geographic Daylight in the New Room Renderer

- Status: Accepted
- Date: 2026-10-24
- Supersedes: the fixed daily sun path in ADR 0014

## Context

The new studio separates session settings, room loading and RealityKit lighting. Its original sun stayed east all day and direct-light shadows were disabled. A real east-facing window loses direct sun when the sun passes behind its facade, while diffuse sky light remains.

## Decision

Use the existing pure SolarEphemerisEngine boundary to calculate geometric elevation and clockwise true-north azimuth from a UTC instant, latitude and longitude using the [NOAA fractional-year equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF). Civil date and slider time are resolved with an explicit time zone before calculating the sun position.

The mock reference is Jakarta (-6.2088, 106.8456), 2026-10-24, Asia/Jakarta. These are demonstration inputs, not measured user coordinates. SolarSimulationContext stores the date, site, time zone and clockwise true-north bearing of the room's -Z axis. At zero heading, +X is east, +Y up and -Z north. The context travels with the confirm/discard draft. ADR 0019 adds saved room-heading input; site and date remain demonstration values rather than user-controlled settings.

A shadow-casting spotlight outside the window approximates sunlight. Increasing its distance to 12 meters reduces divergence; cone angles are measured from the beam axis, not doubled. The east facade's +X outward normal gates direct light by incidence and smoothly fades grazing angles. The retained wall and frame clip the beam; transparent glass does not cast an opaque shadow. Direct sun is zero below the geometric horizon or behind the facade. A separate cooler window sky light continues through civil twilight and casts furniture shadows. Artificial fixtures remain independent.

## Alternatives

A fixed sine curve cannot represent longitude, seasons or room orientation. An unrestricted directional light would illuminate through the cutaway ceiling and removed walls. The window spotlight preserves the existing renderer without reintroducing that leak across the entire room.

## Consequences

Solar direction is geographic; intensity and temperature are clear-sky artistic approximations, not a calibrated lux or energy model. There is no weather, nearby-building occlusion, atmospheric refraction, or global illumination. A finite spotlight still diverges and the cutaway model is not a complete physical enclosure. Geographic inputs are intended for valid latitudes, longitudes and Gregorian dates. Runtime-specific shadow rendering must be checked visually in addition to unit tests.

## Validation

Unit coverage checks an equatorial equinox noon, polar summer/winter, east-to-west travel, room-heading rotation, east-window afternoon rejection, night shutdown, independent artificial lights, and draft rollback. Existing stale tests for the replaced renderer are migrated to the new rig.

Visual verification on the available iOS 27 simulator remains blocked: RealityKit logs `meshShadowCasterProgrammableBlending` pipeline compilation failure (`reading from a rendertarget is not supported`). Morning, afternoon and night captures remain uniformly lit despite updated controls. This is not a visual pass; check rendering on a supported physical device before accepting exposure or shadow quality. The temporary studio launch harness was removed after the check.
