# ADR 0012: Lighting Simulation Modal Session

- Status: accepted
- Date: 2026-10-22

## Context

The lighting simulation UI is needed before the 3D renderer is connected. Users must be able to confirm or discard toggle and time edits without changing persisted fixtures.

## Decision

The studio owns confirmed and draft value-type settings for its current view lifetime. Opening the sheet copies confirmed settings into the draft. The checkmark confirms both fields; the close button or interactive dismissal discards them. The default is lights on at 12.00. Time ranges from 00.00 to 23.59 in one-minute increments.

## Consequences

The modal currently changes UI state only. It does not update SwiftData, artificial light entities, sunlight, or the renderer. Confirmed choices survive reopening within the same studio session and reset when a new studio is created. The studio remains a placeholder with a lighting button; app navigation to the studio is outside this task. Use the Studio3DView Xcode preview to exercise the sheet.

## Validation

Swift Testing covers draft isolation, confirm and reopen, discard, initial values, and time labels at day boundaries.
