# ADR 0009: Dimensional Precision, Oriented Bounding Box, and Plaster Wall Snapping

* Status: accepted
* Date: 2026-10-22
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Following physical on-device LiDAR scanning tests in real-world residential rooms and offices, three critical dimensional defects were discovered:
1. **Camera-Relative Dimension Inflation**: When scanning a 4m × 5m room from a corner or angled heading, an axis-aligned bounding box (AABB) in camera world coordinates projected the room diagonally, artificially inflating measurements to 7.9m × 7.9m. Furthermore, forcing `min` and `max` on axes transposed room dimensions for wide rooms ($W > L$).
2. **Drywall Penetration in Wall Snapping**: Furniture was projected directly onto the wall's mathematical centerline without factoring in wall thickness ($T = 0.10\text{ m}$). Consequently, every snapped item was embedded $5\text{ cm}$ deep inside the physical drywall plaster.
3. **Rotational Divergence ($2\theta$ Angle Error)**: The yaw extraction formula `atan2(col0.z, col0.x)` produced $-\theta$ in ARKit's right-handed coordinate system. Passing this negative angle into RealityKit's `simd_quatf` rotated furniture in reverse relative to the room walls.

We must define an exact mathematical specification to guarantee 1:1 true-to-life dimensional accuracy.

## Decision Drivers

* **1:1 Lifesize Precision**: Measured room dimensions must match physical tape measurements within $\pm 5\text{ cm}$, independent of initial camera scan angle.
* **Ergonomic Clearance Integrity**: Furniture back faces must rest flush against the inner drywall plaster surface ($0\text{ cm}$ penetration, $0\text{ cm}$ floating gap).
* **Orthogonal Angle Preservation**: Furniture placed parallel or perpendicular to walls must snap to the nearest orthogonal heading ($\text{wallYaw} + k \cdot \frac{\pi}{2}$).
* **Sub-Second Testability**: Pure domain functions must be deterministic and verifiable in unit tests without hardware.

## Considered Options

1. **Option 1: Raw Unsnapped LiDAR Bounding Boxes**:
   Render detected boxes exactly where LiDAR placed them with zero wall snapping.
   * *Rejected*: Small measurement noise (floating 2–4 cm away from walls or slightly clipping into them) degrades user trust and looks unpolished.
2. **Option 2: Continuous 1-Master Uniform Scaling**:
   Scale 1 master 3D model uniformly by width.
   * *Rejected*: Violates human ergonomics. A Twin bed becomes 1.25m long (too short for an adult), and a wide desk becomes 1.13m high (armpit height).
3. **Option 3: Oriented Bounding Box (OBB) with Plaster-Face Snapping and Synchronized Quaternions**:
   - Compute room dimensions along the dominant wall heading via OBB.
   - Snap furniture to the inner drywall face by offsetting from centerline by $\frac{T_\text{wall}}{2} + \text{halfDepth}_\text{obj}$.
   - Unify yaw as $\text{atan2}(-\mathbf{col}_0.z, \mathbf{col}_0.x)$ to align ARKit and RealityKit rotations.
   - Classify items into discrete ergonomic archetypes (Twin/Queen/King, Compact/Executive).

## Decision Outcome

Chosen option: **Option 3: Oriented Bounding Box (OBB) with Plaster-Face Snapping and Synchronized Quaternions**.

### Mathematical Specification

1. **Oriented Bounding Box (OBB) Dimension Calculation (`RoomDimensionCalculator`)**:
   - Extract dominant wall yaw $\theta_\text{dominant}$ from the longest detected wall.
   - Project all wall endpoints into room-aligned space $(X', Z')$ rotated by $\theta_\text{dominant}$:
     $$X' = X\cos\theta - Z\sin\theta$$
     $$Z' = X\sin\theta + Z\cos\theta$$
   - Width is span along dominant wall axis ($X'$), Length is span along perpendicular axis ($Z'$).

2. **Plaster-Face Snapping (`RoomCaptureSanitizer`)**:
   - Given closest wall segment $AB$, project furniture center $P$ onto segment: $Q = A + t\hat{v}$.
   - Compute relative angle $\Delta\theta = \text{yaw}_\text{obj} - \text{yaw}_\text{wall}$.
   - Compute true object half-depth along wall normal:
     $$\text{halfDepth} = \frac{|\sin\Delta\theta| \cdot \text{dim}_x + |\cos\Delta\theta| \cdot \text{dim}_z}{2}$$
   - Position object flush against plaster face:
     $$P_\text{snapped} = Q + \hat{n} \cdot \left(\frac{T_\text{wall}}{2} + \text{halfDepth}\right)$$
   - Snap yaw to nearest orthogonal multiple $k \in \{0, 1, 2, 3\}$ within $15^\circ$:
     $$\text{snappedYaw} = \text{yaw}_\text{wall} + k \cdot \frac{\pi}{2}$$

3. **Unified Right-Handed Coordinate Rotation**:
   $$\text{yaw} = \text{atan2}(-\mathbf{col}_0.z, \mathbf{col}_0.x)$$
   Guarantees $\text{simd\_quatf}(\text{angle: yaw, axis: } [0, 1, 0])$ rotates identically to the room walls in RealityKit.

### Consequences

* Dimensions of an angled $4\text{m} \times 5\text{m}$ room remain $4.0\text{m} \times 5.0\text{m}$ without inflation.
* Zero drywall clipping: furniture rests flush against walls.
* Desks and beds placed perpendicular or parallel to walls lock to crisp $90^\circ$ architectural alignments.
