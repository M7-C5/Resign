# ADR 0039: On-Device Apple Foundation Models Integration for Spatial Diagnostics

* Status: accepted
* Date: 2026-10-23
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

Resign previously utilized a deterministic rulebook implementation (`RulebookAIDiagnosticService`) as a placeholder to simulate LLM spatial reasoning and solver parameterization. With the target platform set to iOS 27 (`IPHONEOS_DEPLOYMENT_TARGET = 27.0`), Apple's native on-device and Private Cloud Compute AI framework (`FoundationModels.framework`) is available.

We need to transition the diagnostic pipeline from synthetic rulebook generation to real Apple Foundation Model inference (`LanguageModelSession`) while ensuring:
1. Pure local, privacy-first inference without requiring third-party API keys or unvetted cloud dependencies.
2. Resilience across headless CI environments, simulator runs without downloaded model weights, and hardware capability differences.
3. Strict adherence to our existing contracts: compact centimeter prompts, boundary instructions forbidding 3D math hallucinations, and output validation gatekeeping.

## Decision Drivers

* **Native iOS 27 Architecture**: Leverage Apple's first-party `FoundationModels.framework` (`SystemLanguageModel`, `LanguageModelSession`, and `PrivateCloudComputeLanguageModel`).
* **Privacy & Offline Operation**: Keep user home interior data on-device or secured via Private Cloud Compute with Apple Intelligence.
* **Deterministic Fallback for Headless CI**: Seamlessly fall back to rulebook synthesis when running in simulators or environments where system model assets are not initialized.
* **Zero Disruption to Downstream Pipeline**: Maintain identical input contracts (`Room`, `Layout`, `SpatialViolation`) and output contracts (`AIDiagnosticResponse`, `SolverSettings`, `AIDiagnosticValidator`).

## Considered Options

* **Option 1: Third-Party Cloud LLM (OpenAI / Gemini HTTP API)**:
  - *Rejected*: Requires external API keys, internet connectivity, and leaks private room/home spatial layouts to third-party cloud servers.
* **Option 2: Pure FoundationModels with Hard Failure on Unavailable**:
  - *Rejected*: Fails headless unit tests and simulators that lack local neural engine weights.
* **Option 3: Resilient FoundationModels Diagnostic Service with Fallback**:
  - Uses `LanguageModelSession` with `SystemLanguageModel.default` when available on iOS 27.
  - Decodes structured JSON responses from the foundation model output.
  - Passes output through `AIDiagnosticValidator` to eliminate hallucinated UUIDs.
  - Gracefully falls back to `RulebookAIDiagnosticService` when system model weights are not loaded.

## Decision Outcome

Chosen option: **Option 3: Resilient FoundationModels Diagnostic Service with Fallback**.

### System Architecture

```
[SpatialClearanceEngine]
          │
          ▼ (Measured Violations)
[RoomDiagnosticPromptBuilder]
          │
          ▼ (Compact cm Prompt + Strict System Instructions)
[FoundationModelAIDiagnosticService]
    ├── SystemLanguageModel.default.isAvailable == true:
    │     LanguageModelSession.respond(to:) ──► Live Foundation Model Output
    └── SystemLanguageModel.default.isAvailable == false (Simulator / CI):
          RulebookAIDiagnosticService ────────► Deterministic Reference Output
          │
          ▼ (Raw JSON Response)
[AIDiagnosticValidator] (Strips Hallucinated UUIDs & Clamps Weights)
          │
          ▼
[LayoutOptimizerEngine] ──► 3 Distinct Layout Variants
```

### Consequences

#### Positive Consequences
* Real AI semantic reasoning and human-centric explanations are generated dynamically by Apple Foundation Models on iOS 27.
* Zero third-party network egress or external API keys needed.
* 100% CI/simulator pass rate retained via automated availability inspection.
* Seamless integration with existing `AIDiagnosticServiceProtocol`.

#### Negative Consequences
* First-time model initialization on device requires local Apple Intelligence assets to be present.
