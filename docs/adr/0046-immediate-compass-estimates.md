# ADR 0046: Immediate Compass Estimates with Visible Accuracy

- Status: Accepted
- Date: 2026-11-03
- Amends: [ADR 0044](0044-automatic-north-calibration-during-room-scan.md)

## Context

Requiring heading accuracy of 20 degrees before accepting any direction leaves indoor scans without north indefinitely. A compass can supply a useful approximate direction even when its reported uncertainty exceeds that threshold.

## Decision

Accept the first finite true-heading reading with nonnegative sensor accuracy and a matching horizontal AR camera reference as a provisional estimate. Show and persist its reported uncertainty. Label the scan badge and lighting-plan arrow Estimated until at least five accurate samples span two seconds and pass the existing circular consistency check. Refine using samples with accuracy no worse than 20 degrees. A refined result supersedes a provisional one; later poor readings do not downgrade it in the same AR world.

Retain the existing snapshot format. Provisional records contain one sample, while refined records contain at least five accurate samples. Calibration quality is derived from that metadata. Preserve the existing distinction between unavailable heading and valid but coarse heading. This uses true heading; it does not substitute magnetic north without labeling it.

## Consequences

Users can finish a scan and see an estimated north arrow without waiting for indoor compass precision to improve. The arrow and daylight orientation may be inaccurate by the displayed uncertainty. Invalid readings with negative sensor accuracy remain rejected. Hardware availability, location permission, and a valid true-heading reading are still required.

## Validation

Tests cover immediate estimates at 45-degree uncertainty, refinement after accurate observations, inconsistent readings remaining provisional, invalid readings, high-frequency callbacks, and persistence of both provisional and refined records. Run the repository verification script for build and isolated unit tests.
