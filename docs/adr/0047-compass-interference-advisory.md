# ADR 0047: Advisory Compass Interference Warning During Room Scanning

- Status: Accepted
- Date: 2026-11-04
- Amends: [ADR 0046](0046-immediate-compass-estimates.md)

## Context

Indoor compass precision can remain poor near magnetic accessories or metal. Users need guidance while scanning without mistaking low precision for proof that a particular case contains a magnet.

## Decision

Use existing Core Location heading callbacks for a transient advisory monitor. The magnitude of heading x/y/z components is measured in microteslas. A magnitude of at least 100 microteslas lasting two seconds produces a possible-interference warning. Independently, accuracy of at least 25 degrees or invalid negative accuracy lasting three seconds produces a low-accuracy warning. These are conservative product heuristics, not validated identification of a magnetic case or a magnet.

Clear the warning after three seconds of accuracy within 20 degrees and available field magnitude no greater than 80 microteslas. Missing field values alone do not trigger a warning. Expire stale warnings after three seconds without readings, and restart evidence collection after callback gaps exceeding 1.5 seconds. Ignore duplicate and out-of-order samples.

Show an inline, accessible material banner during scanning. Describe casing, accessories, and nearby metal as possible causes, and suggest removing magnetic accessories or moving away from metal. Do not block capture or change north estimate acceptance. Reset advisory state when tracking restarts. No additional sensor permission, persistence, or geographic data is introduced.

## Consequences

The warning can guide users with approximately 30-degree compass precision even when field magnitude is unavailable. It cannot reliably identify every magnet, distinguish a case from another source, or establish that poor accuracy was caused by magnetism. Thresholds require on-device observation; unit tests validate timing and state behavior only.

## Validation

Tests cover brief spikes, sustained fields, sustained poor and invalid accuracy, recovery, expiry, missing field values, and callback gaps or reversed timestamps. Run the repository build and isolated unit tests.

## References

- [Apple: CLHeading x components](https://developer.apple.com/documentation/corelocation/clheading/x)
- [Apple: heading accuracy](https://developer.apple.com/documentation/corelocation/clheading/headingaccuracy)
