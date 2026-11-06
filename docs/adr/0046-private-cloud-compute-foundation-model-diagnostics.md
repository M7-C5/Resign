# ADR 0046: Private Cloud Compute Foundation Model Integration for Spatial Diagnostics

* Status: accepted
* Date: 2026-11-06
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign previously integrated Apple's native on-device `SystemLanguageModel.default` (ADR 0039) for spatial diagnostics and layout parameterization on iOS 27. While on-device inference delivers immediate local intelligence, complex architectural reasoning, nuanced free-text constraint extraction, and comprehensive multi-room circulation analysis benefit significantly from Apple's server-scale Private Cloud Compute (PCC) Foundation Models (`PrivateCloudComputeLanguageModel`).

Apple Intelligence on iOS 27 introduces `PrivateCloudComputeLanguageModel` within `FoundationModels.framework`, offering powerful cloud-scale foundation model capacity backed by hardware security, cryptographic attestability, and strict non-retention privacy guarantees.

We need to upgrade the diagnostic pipeline to:
1. Prefer Apple Private Cloud Compute Foundation Model inference (`PrivateCloudComputeLanguageModel`) on iOS 27 by default.
2. Provide seamless fallback to on-device Neural Engine inference (`SystemLanguageModel.default`) when network or cloud capacity is constrained.
3. Preserve deterministic rulebook fallback (`RulebookAIDiagnosticService`) for headless CI and simulator environments.
4. Maintain strict adherence to compact centimeter prompts, zero 3D math hallucinations, and output validation gatekeeping.

## Decision Drivers

* **Scale & Reasoning Depth**: Private Cloud Compute provides larger parameter capacity for multi-variable ergonomics synthesis while matching Apple's architectural standards.
* **Apple Cryptographic Privacy**: PCC guarantees that home interior spatial data is never retained, logged, or accessible to Apple or third parties.
* **Multi-Tier Resilience**: Tiered fallback from Private Cloud Compute → On-Device Foundation Model → Rulebook Engine guarantees 100% test reliability and zero user dead ends.
* **Contract Integrity**: Retain identical input contracts (`Room`, `Layout`, `SpatialViolation`, `RoomPreference`) and output contracts (`AIDiagnosticResponse`, `SolverSettings`, `AIDiagnosticValidator`).

## Considered Options

* **Option 1: Exclusive Private Cloud Compute without Fallback**:
  - *Rejected*: Fails when offline or during transient network interruptions.
* **Option 2: Third-Party Cloud LLM**:
  - *Rejected*: Incompatible with Apple HIG and privacy guidelines for home and interior scans.
* **Option 3: Tiered Private Cloud Compute Foundation Model Service**:
  - Prioritizes `PrivateCloudComputeLanguageModel` on iOS 27.
  - Automatically falls back to on-device `SystemLanguageModel.default` when PCC is unavailable.
  - Gracefully falls back to `RulebookAIDiagnosticService` in headless test environments.
  - Transparently reflects the active compute tier via `DiagnosticEngineSource.privateCloudCompute`.

## Decision Outcome

Chosen option: **Option 3: Tiered Private Cloud Compute Foundation Model Service**.

### Architecture & Routing Flow

```
[SpatialClearanceEngine]
          │
          ▼ (Measured Violations)
[RoomDiagnosticPromptBuilder]
          │
          ▼ (Compact cm Prompt + Strict System Instructions)
[FoundationModelAIDiagnosticService (computeTarget: .privateCloudCompute)]
    ├── 1. PrivateCloudComputeLanguageModel.isAvailable == true:
    │        LanguageModelSession(model: PrivateCloudComputeLanguageModel()) ──► Private Cloud Compute Live Output
    ├── 2. SystemLanguageModel.default.isAvailable == true:
    │        LanguageModelSession(model: SystemLanguageModel.default) ────────► On-Device Neural Engine Output
    └── 3. Offline / Test Environment / Simulators:
             RulebookAIDiagnosticService ─────────────────────────────────────► Deterministic Reference Output
          │
          ▼ (Raw JSON Response)
[AIDiagnosticValidator] (Strips Hallucinated UUIDs & Enforces Panero & Zelnik Tolerances)
          │
          ▼
[LayoutOptimizerEngine] ──► 3 Distinct Layout Variants
```

### Consequences

#### Positive Consequences
* Spatial reasoning and layout insights leverage server-scale Apple Intelligence Foundation Models on iOS 27.
* Full privacy preserved via hardware-enforced, cryptographically verifiable Private Cloud Compute.
* Zero disruptions to headless automated verification or offline devices.
* UI transparently reports the active engine tier with dedicated badge indicators.

#### Negative Consequences
* Initial PCC requests require network connectivity.

