---
name: recast-license-gating
description: "Use when asked to gate a feature, add gating, make functionality license-gated or licensed-only, or review Recast license checks in OSDCloud. Gating always means requiring a valid Recast license, not merely registration."
---

# Recast license gating

In this repository, **gating always means requiring a valid Recast license**.
Do not substitute registration status, email presence, a license filename,
profile settings, environment flags, or a new feature flag for license validity.

## Workflow

1. Identify the feature's entry points, shared helpers, and explicitly ungated
   behavior. Gate discovery and side effects, not just the final action.
2. Reuse [Get-OSDCoreLicense](../../../OSDCloud/private/core-license/Get-OSDCoreLicense.ps1)
   and require its selected license's `IsValid` result to be true.
   `OSDCoreLicense.IsRegistered` only records email presence and is not equivalent.
   Startup can run before global license state is initialized.
3. Match the requested denial UX:
   - For quiet skipping, return without warnings, errors, prompts, registration
     guidance, or success/failure summaries for skipped work. License lookup
     failures must fail closed; keep diagnostics generic and verbose-only.
   - For explicit denial, use the applicable existing warning/guidance pattern.
     Do not silence unrelated operational failures.
4. Reuse [Test-WinpeStartupAssetLicense](../../../OSDCloud/private/WinpeStartup/Test-WinpeStartupAssetLicense.ps1)
   for quiet WinpeStartup asset gating. Core and selected-profile `.env`, `.reg`,
   and `.cer` imports are gated; profile JSON, JSON `env`/`Environment`, and
   built-in shell initialization remain ungated.
5. Do not use [Test-OSDeployLicenseGate](../../../OSDCloud/private/core-license/Test-OSDeployLicenseGate.ps1)
   for quiet startup imports: it warns, displays registration guidance, and has
   a hydration-specific bypass. Never broaden a bypass to another feature.
6. Test valid, missing, invalid, and failed lookups using synthetic license
   objects. Prove skipped work has no discovery/import side effects and no
   denial warnings/errors, while ungated behavior continues. Retain licensed
   failure-handling and normal-behavior regression tests.
7. Update the feature's help and documentation with the entitlement boundary.

## Validity policy

Follow the existing `Get-OSDCoreLicense` `IsValid` semantics unless the user
explicitly requests a licensing-policy change. The current reader validates
schema fields, permits expired candidates, and does not cryptographically verify
signatures. Do not claim `IsValid` proves expiration enforcement or signature
authenticity. Do not implement a parallel validator or change expiration,
activation, license selection, or signature policy as an incidental feature fix.

Never read, log, or embed real license payloads or personal data in tests,
documentation, or diagnostic output.
