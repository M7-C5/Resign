# ADR 0017: Window-Shaped Direct Sunlight

- Status: Accepted
- Date: 2026-10-25
- Amends: [ADR 0016](0016-simulator-daylight-fallback.md)

## Context

Disabling all spotlight shadows on the simulator restored visible light but left the direct sunlight patch circular. A spotlight cone describes the source's coverage, not the shape of the window opening.

## Decision

Require direct-sun shadow mapping on both simulator and physical device, independently of the optional diffuse-sky and fixture shadows. The retained east wall segments and window frame clip the source to the actual loaded opening. Glass remains transparent to shadow casting. The mullion divides the sunlight patch according to the model geometry.

Use a spotlight cone wider than the window diagonal, with a gradual intensity falloff between its inner and outer angles. This keeps the circular source boundary outside the aperture and softens the edge; the east wall, frame, and mullion shape the beam that reaches the room. Geographic sun direction still controls the patch's position and perspective throughout the morning.

Keep diffuse skylight active whenever the sun is above the horizon, independently of direct-sun incidence at the east facade. Use a broad window fill plus a 48,000-lumen unshadowed bounce near the room center, not at the facade. This keeps the room bright around noon after direct sunlight has moved behind the window and avoids a concentrated glow around the opening. This supersedes ADR 0016's 24,000-lumen bounce at the window plane.

Keep the environment override, distance compensation, afternoon rejection, night shutdown, and independent lamp control from ADR 0016.

## Consequences

The direct sunlight footprint follows the window aperture with a soft cone edge instead of exposing a hard circular source boundary. Shadow mapping is required for this contract; a runtime without working spotlight shadows cannot provide an equivalent unshadowed fallback. The sun remains a finite-distance approximation and does not model glass refraction or global illumination.

## Validation

Unit coverage loads the actual room and checks that all four east wall segments and the mullion remain active shadow casters, glass does not cast an opaque shadow, direct-sun shadows are present in the simulator, the cone has a feathered edge while covering the window diagonal, and noon retains diffuse fill when the east window rejects direct sun.

An aperture-coverage regression checks that the cone reaches beyond every window corner. Simulator spotlight shadows render successfully after the exposure and environment fixes; the earlier pipeline warning does not justify removing direct-sun occlusion on the verified iOS 26.5 runtime.

Visual verification on the iOS 26.5 iPhone 17 simulator at 08:00 with lamps off shows a straight-edged window projection, the mullion's dividing shadow, and furniture occlusion. The final fast verification gate passes all 34 unit tests. Physical-device shadow quality remains unverified.
