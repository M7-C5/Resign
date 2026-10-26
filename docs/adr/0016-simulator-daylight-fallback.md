# ADR 0016: Simulator Daylight Rendering Fallback

- Status: Accepted
- Date: 2026-10-25
- Amends: [ADR 0015](0015-geographic-mock-daylight.md)
- Shadow fallback amended by: [ADR 0017](0017-window-shaped-sunlight.md), which requires direct-sun shadows on the verified simulator runtime to preserve the window silhouette.

## Context

The simulator shadow pipeline failure recorded in ADR 0015 prevents shadowed daylight from appearing. Both natural sources use shadows, whereas artificial fixtures also have an unshadowed point fill. This makes lamps appear to work while natural light is absent.

## Decision

Default the room lighting rig to unshadowed lights when compiled for the simulator, including SwiftUI simulator previews. Keep dynamic shadows enabled by default on physical devices. The existing tuning override remains available for renderer diagnostics and explicit shadow tests.

Keep geographic sun direction, east-window incidence, twilight, source positions, and artificial-light switching unchanged. Do not replace natural illumination with emissive room materials or lamp fill.

Explicitly assign an image-based light with source `.none` and its receiver to the studio root, and set its environment-lighting weight to zero. This prevents the default non-AR environment from washing out the lighting comparison. The root policy is inherited by its descendants and leaves explicit spot and point lights active. See Apple's [environment-lighting configuration documentation](https://developer.apple.com/documentation/realitykit/environmentlightingconfigurationcomponent).

Compensate direct-source lumens by the squared ratio of beam distance to the original 3-meter exposure reference. Moving the source to 12 meters to reduce divergence otherwise loses most of its visible illumination. The tuning's sunlight lumens refer to that 3-meter reference; they are an artistic exposure setting, not measured solar flux.

Add an unshadowed point fill at the window's interior sky source to approximate diffuse daylight bounce. Its 24,000-lumen exposure follows the existing skylight curve and color, including twilight and night shutdown, independently of lamps. RealityKit does not calculate real-time global illumination, so a direct patch alone leaves the rest of the room almost black once automatic environment lighting is suppressed. This fill is an artistic bounce approximation and can illuminate through furniture or nearby wall surfaces.

## Consequences

Simulator previews can show time-varying daylight without relying on the failing shadow pipeline. They approximate illumination: walls, window mullions, and furniture do not occlude light there. Use a physical device to evaluate window-shaped patches and furniture shadows. This is a compile-time runtime policy, not automatic GPU failure detection.

## Validation

Unit tests check the platform defaults, absence of simulator shadow components, positive morning daylight with lamps off, afternoon sky illumination, and night shutdown. An explicit shadow-enabled test continues to check the device rendering contract. Run the fast verification script without UI performance tests.

Regression tests also check the explicit environment override and the 16-fold intensity compensation when moving the sun source from 3 to 12 meters.

Visual checks on the iOS 26.5 iPhone 17 simulator show a morning sunlight patch and diffuse window illumination with lamps off, and a dark room at midnight. The fast verification gate passes all 32 unit tests. Physical-device shadow quality remains unverified.
