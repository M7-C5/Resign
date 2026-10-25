# ADR 0013: Window-Shaped Direct Sunlight

- Status: Accepted
- Date: 2026-10-25
- Amends: [ADR 0012](0012-simulator-daylight-fallback.md)

## Context

Disabling all spotlight shadows on the simulator restored visible light but left the direct sunlight patch circular. A spotlight cone describes the source's coverage, not the shape of the window opening.

## Decision

Require direct-sun shadow mapping on both simulator and physical device, independently of the optional diffuse-sky and fixture shadows. The retained east wall segments and window frame clip the source to the actual loaded opening. Glass remains transparent to shadow casting. The mullion divides the sunlight patch according to the model geometry.

Use the full spotlight cone at uniform intensity by matching its inner and outer angles. Cover the window diagonal with a full cone angle of `2 * atan(radius / distance)`, including a 10% corner margin. This replaces the half-angle setting in ADR 0011: visual inspection showed that setting cropped the window projection into a curved footprint. The wall and frame determine the illuminated footprint. Geographic sun direction still controls the patch's position and perspective throughout the morning. Diffuse sky bounce remains soft and is not expected to form a sharp window silhouette.

Keep the environment override, distance compensation, afternoon rejection, night shutdown, and independent lamp control from ADR 0012.

## Consequences

The sunlight footprint follows the window aperture instead of the circular source boundary. Shadow mapping is required for this contract; a runtime without working spotlight shadows cannot provide an equivalent unshadowed fallback. The sun remains a finite-distance approximation and does not model glass refraction or global illumination.

## Validation

Unit coverage loads the actual room and checks that all four east wall segments and the mullion remain active shadow casters, glass does not cast an opaque shadow, direct-sun shadows are present in the simulator, and source cone intensity remains uniform across its coverage.

An aperture-coverage regression checks that the cone reaches beyond every window corner. Simulator spotlight shadows render successfully after the exposure and environment fixes; the earlier pipeline warning does not justify removing direct-sun occlusion on the verified iOS 26.5 runtime.

Visual verification on the iOS 26.5 iPhone 17 simulator at 08:00 with lamps off shows a straight-edged window projection, the mullion's dividing shadow, and furniture occlusion. The final fast verification gate passes all 34 unit tests. Physical-device shadow quality remains unverified.
