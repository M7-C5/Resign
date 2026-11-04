# ADR 0048: Automatic North Calibration During Room Scan

The strict acceptance threshold is amended by [ADR 0046](0046-immediate-compass-estimates.md), which permits provisional compass estimates with visible uncertainty.

- Status: Accepted
- Date: 2026-11-03
- Amends: [ADR 0021](0021-room-north-alignment.md), [ADR 0036](0036-remove-standalone-compass.md)

## Context

The standalone post-scan compass screen was removed, leaving scanned rooms with a default zero bearing. Daylight simulation needs the direction of the saved room plan relative to true north, but users should not have to stop scanning to align a marker.

## Decision

While RoomPlan is actively scanning in the foreground, select the device edge with a stable horizontal projection (portrait top / camera -X, or landscape-left top / camera +Y) and match Core Location heading orientation to that edge. Pair readings whose timestamps differ by at most 200 ms, convert each pair into an AR-world bearing, and combine consistent bearings with an accuracy-weighted circular mean. Accept a calibration only with at least five readings across two seconds, heading accuracy of 20 degrees or better, and a circular concentration of at least 0.98.

Convert the accepted AR-world bearing to the room plan's local -Z bearing using the saved plan yaw. Store the calibration record in the optional `RoomPlanSnapshot` field and store the resulting room bearing in `Room.compass`. Do not persist the user's geographic coordinates. Existing snapshots without the optional field continue to decode.

Show a compact status badge while scanning that distinguishes searching, successful calibration, temporary pauses, missing location permission, unavailable compass hardware, and scans that ended without a reliable result. In Configure Lighting, rotate a north arrow using the saved room bearing and label it as unknown when no calibration record exists.

Location authorization and reliable sensor readings are optional for completing a scan. If permission is denied or readings are stale, inaccurate, inconsistent, or unavailable, leave the north calibration absent and retain the existing default bearing. Stop heading and location updates when scanning ends, the scan screen leaves, or the app enters the background; resume sampling if the same scan returns to the foreground.

## Consequences

Rooms with a reliable scan-time estimate align daylight simulation without a separate calibration step, and users can see the result in both scan status and the room plan. Results can remain uncalibrated on devices without a magnetometer or when the user denies location access. The sensor adapter samples the existing RoomPlan AR session and does not replace its delegate.

## Validation

Pure estimator tests cover camera rotation compensation, plan-yaw conversion, circular wraparound, stale readings, vertical camera poses, low accuracy, and inconsistent bearings. Mapper tests cover persistence and decoding snapshots created before the optional calibration field existed.

The scan permission badge opens app Settings when access is denied. Generated device and simulator app Info.plists must contain the location usage description. A valid true heading is accepted without a separate arbitrary geographic-accuracy cutoff. An accepted world bearing survives until scan completion; tracking loss or an edge-reference change invalidates it. The sampling timer runs in common run-loop modes so touch gestures do not suspend it. Regression tests cover upright portrait and landscape reference selection.

Compass samples are spaced at least 200 ms apart before entering the ten-second estimator window. This prevents frequent callbacks from exhausting a fixed-size buffer before the required two-second observation span. Scan feedback distinguishes waiting for true heading, poor compass accuracy, and accepted-reading collection. Finishing before calibration explicitly warns that north will remain unknown. Inactive transitions during processing preserve the frozen estimate. Regression tests replay 100 Hz heading callbacks over four seconds.
